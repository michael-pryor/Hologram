//
//  SoundPlayback.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import "SoundPlayback.h"
#import "SoundEncodingShared.h"
#import "BlockingQueue.h"
#import "Signal.h"
#import <mach/mach_time.h>
#import "AverageTracker.h"

@import AVFoundation;

// We think that each buffer is 125ms in length.
#define ESTIMATED_BUFFER_SIZE_MS 125

// When determining what delay to impose on video, we count the number of buffers within a time period. Ideally
// we would set this to equal ESTIMATED_BUFFER_SIZE_MS but is is essential that we do not overestimate the value
// so we include a grace value, such that we end the count early.
#define BUFFER_GRACE_MS 50


@implementation SoundPlayback {
    AudioStreamBasicDescription *_audioDescription;
    AudioQueueRef _audioQueue;
    Signal *_isPlaying;
    Signal *_isNoExternalPause;

    BlockingQueue *_soundQueue;

    // Buffers which were returned to the pool.
    // because there was nothing ready in _soundQueue.
    BlockingQueue *_bufferPool;

    // Thread blocks on the sound queue and pushes data out to the output thread.
    NSThread *_soundQueueThread;
    Signal *_soundQueueThreadTerminated;

    NSThread *_outputThread;
    CFRunLoopRef _outputThreadRunLoop;
    Signal *_outputThreadTerminated;

    uint _numAudioBuffers;
    AudioQueueBufferRef *_audioBuffers;
    uint _bufferSizeBytes;
    uint _maxQueueSize;
    Signal *_queueSetup;
    id <SoundPlaybackDelegate> _soundPlaybackDelegate;
    id <MediaDelayNotifier> _mediaDelayDelegate;

    Byte *_magicCookie;
    int _magicCookieSize;

    volatile bool _forceRestart;
    volatile bool _flush;

    AverageTracker *_averageTracker;
    Signal *_running;

}


- (id)initWithAudioDescription:(AudioStreamBasicDescription *)description numBuffers:(uint)numBuffers maxPendingAmount:(uint)maxAmount soundPlaybackDelegate:(id <SoundPlaybackDelegate>)soundPlaybackDelegate mediaDelayDelegate:(id <MediaDelayNotifier>)mediaDelayDelegate {
    self = [super init];
    if (self) {
        _bufferSizeBytes = calculateBufferSize(description);
        _numAudioBuffers = numBuffers;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numAudioBuffers);
        _maxQueueSize = maxAmount;

        _audioDescription = description;
        _soundQueue = [[BlockingQueue alloc] initWithMaxQueueSize:_maxQueueSize];

        // We track the number of additions to the queue which have taken place in last x ms.
        // We don't track the actual queue size because this is liable to increase and decrease rapidly.
        float estimatedBufferSizeSeconds = ((float) ESTIMATED_BUFFER_SIZE_MS) / 1000.0f;
        float graceSeconds = ((float) BUFFER_GRACE_MS) / 1000.0f;
        float trackingPeriod = estimatedBufferSizeSeconds - graceSeconds;
        NSLog(@"Tracking period is: %.2f", trackingPeriod);
        [_soundQueue setupEventTracker:trackingPeriod];

        _bufferPool = [[BlockingQueue alloc] init];

        // In edge cases we may end up trying to reinsert items to the queue; duplicates would be catestrophic.
        [_bufferPool enableUniqueConstraint];

        _queueSetup = [[Signal alloc] initWithFlag:false];
        _isPlaying = [[Signal alloc] initWithFlag:false];
        _isNoExternalPause = [[Signal alloc] initWithFlag:true];

        _soundPlaybackDelegate = soundPlaybackDelegate;

        _mediaDelayDelegate = mediaDelayDelegate;

        [self resetAverageTracker];

        _forceRestart = false;
        _flush = false;

        _running = [[Signal alloc] initWithFlag:false];
        _outputThreadTerminated = [[Signal alloc] initWithFlag:false];
        _soundQueueThreadTerminated = [[Signal alloc] initWithFlag:false];

        [self selectSpeaker];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:nil];
    }
    return self;
}

// Create a new tracker, so old values are lost. Important because
// when we switch between people, they may send at different rates.
- (void)resetAverageTracker {
    // 60 second rolling average.
    _averageTracker = [[AverageTracker alloc] initWithExpiry:60];
}

// Return buffer to pool to be reused.
- (void)returnToPool:(AudioQueueBufferRef)audioBuffer {
    NSValue *nsValue = [NSValue value:&audioBuffer withObjCType:@encode(AudioQueueBufferRef)];
    [_bufferPool add:nsValue];
}

- (void)dealloc {
    free(_audioBuffers);
}

- (bool)shouldReturnBuffer {
    return _forceRestart || _flush;
}

- (void)shutdown {
    if ([_queueSetup clear]) {
        [self stopPlayback:false];
        [_soundQueue restartQueue];
    }
}

- (void)resetQueue {
    [_soundQueue restartQueue];
}

- (void)setMagicCookie:(Byte *)magicCookie size:(int)size {
    _magicCookie = magicCookie;
    _magicCookieSize = size;
}

// Empty the pool and repopulate from scratch.
- (void)resetPool {
    @synchronized (self) {
        [_bufferPool clear];
        for (int n = 0; n < _numAudioBuffers; n++) {
            [self returnToPool:_audioBuffers[n]];
        }
    }
}

- (void)playSoundData:(ByteBuffer *)packet withBuffer:(AudioQueueBufferRef)inBuffer {
    if (![self shouldAttemptEnqueue]) {
        return;
    }

    // Copy byte buffer data into audio buffer.
    uint unreadData = packet.getUnreadDataFromCursor;
    if (unreadData > 0) {
        if (unreadData > _bufferSizeBytes) {
            NSLog(@"Incorrectly sized speaker buffer received, expected [%d], received [%d]", _bufferSizeBytes, unreadData);
            unreadData = _bufferSizeBytes;
        }

        memcpy(inBuffer->mAudioData, packet.buffer + packet.cursorPosition, unreadData);
    }

    // Setup format and magic cookie.
    struct AudioStreamPacketDescription *desc = &inBuffer->mPacketDescriptions[0];
    desc->mDataByteSize = unreadData;
    desc->mStartOffset = 0;
    desc->mVariableFramesInPacket = 0;
    inBuffer->mAudioDataByteSize = unreadData;

    struct AudioTimeStamp audioStartTime;

    // Queue buffer.
    OSStatus result = AudioQueueEnqueueBufferWithParameters(_audioQueue,
            inBuffer,
            1,
            desc,
            0,
            0,
            0,
            NULL,
            NULL,
            &audioStartTime);

    if (![self handleResultOsStatus:result description:@"Enqueing speaker buffer"]) {
        [self returnToPool:inBuffer];
        return;
    }

    // Check the current time vs time buffer will be scheduled.
    // If it will be scheduled in the past, this is bad because it won't be played.
    // We're out of sync, so force a restart of the audio queue.
    //
    // If it is scheduled too far in the future then there will be too much delay on
    // audio playback and we should restart the audio queue to catch up again.
    uint64_t currentMachineTime = mach_absolute_time();
    uint64_t audioBufferStartTime = audioStartTime.mHostTime;
    uint64_t thresholdMsFutureMax = 100; // Max acceptable latency.

    // First queued buffer may have start time of 0.
    if (audioBufferStartTime != 0) {
        uint64_t diff;
        bool isInFuture;

        if (currentMachineTime > audioBufferStartTime) {
            diff = currentMachineTime - audioBufferStartTime;
            isInFuture = false;
        } else {
            diff = audioBufferStartTime - currentMachineTime;
            isInFuture = true;
        }

        // Convert from nano seconds to milliseconds.
        uint64_t diffMs = diff / 1000000;

        if (isInFuture) {
            if (diffMs > thresholdMsFutureMax) {
                _flush = true;
            }
        } else {
            if (diffMs > 0) {
                _forceRestart = true;
            }
        }
    }

    // Decode data.
    result = AudioQueuePrime(_audioQueue, 0, NULL);
    if (![self handleResultOsStatus:result description:@"Priming speaker buffer"]) {
        // No guarantee that callback will be called correctly, so
        // reset the whole pool.
        [self resetPool];
    }
}

- (bool)handleResultOsStatus:(OSStatus)result description:(NSString *)description {
    if (HandleResultOSStatus(result, description, false)) {
        return true;
    }

    [self stopPlayback:false];
    return false;
}

// Callback when buffer has finished playing and is ready to be reused.
static void HandleOutputBuffer(void *aqData,
        AudioQueueRef inAQ,
        AudioQueueBufferRef inBuffer) {
    SoundPlayback *obj = (__bridge SoundPlayback *) (aqData);

    // A thread is waiting for all buffers to be returned, make it happen.
    if ([obj shouldReturnBuffer]) {
        [obj returnToPool:inBuffer];
        return;
    }

    ByteBuffer *nextItem = [obj->_soundQueue getWithTimeout:0.2];

    if (nextItem == nil) {
        // Return the buffer to the pool so that it can be reused.
        [obj returnToPool:inBuffer];
        return;
    }

    // Play the next item immediately.
    [obj playSoundData:nextItem withBuffer:inBuffer];
}

- (bool)shouldAttemptEnqueue {
    return [_queueSetup isSignaled] && [_isPlaying isSignaled];
}

- (void)startPlayback {
    [self startPlayback:true];
}

- (void)startPlayback:(Boolean)external {
    if (!external) {
        if ([_isNoExternalPause wait]) {
            NSLog(@"External audio playback pause wait ended");

            // Do not start playback because in order to have reached this point, another thread
            // will have had to start the audio queue.
            return;
        }
    }

    @synchronized (self) {
        if (external) {
            [self resetPool];
        }

        if ([_queueSetup isSignaled] && [_isPlaying signalAll]) {
            OSStatus result = AudioQueueStart(_audioQueue, NULL);
            HandleResultOSStatus(result, @"Starting speaker queue", true);
            [_soundPlaybackDelegate playbackStarted];
        }
    }

    if (external) {
        if ([_isNoExternalPause signalAll]) {
            NSLog(@"External audio playback pause ended");
        }
    }
}

- (void)stopPlayback {
    [self stopPlayback:true];
}

- (void)stopPlayback:(Boolean)external {
    if (external) {
        if ([_isNoExternalPause clear]) {
            NSLog(@"External audio playback pause started");
            [self resetAverageTracker];
        }
    }
    @synchronized (self) {
        if ([_queueSetup isSignaled] && [_isPlaying clear]) {
            OSStatus result = AudioQueueStop(_audioQueue, TRUE);
            HandleResultOSStatus(result, @"Stopping speaker queue", true);

            [_soundPlaybackDelegate playbackStopped];
        }
    }
}

- (void)waitForQueueToFill {
    while ([_soundQueue size] < 3 && [_running isSignaled]) {
        //NSLog(@"Waiting for playback queue to expand");
        [NSThread sleepForTimeInterval:0.01];
    }
}

// Thread polls on sound queue and plays data.
- (void)soundQueueThreadEntryPoint:var {
    [_soundQueueThreadTerminated clear];
    [self waitForQueueToFill];

    while ([_running isSignaled]) {
        // Wait for an available audio buffer.
        NSValue *_bufferVal = [_bufferPool get];
        if (_bufferVal == nil) {
            break;
        }

        // Wait for a new item to play.
        ByteBuffer *nextItem = [_soundQueue get];
        if (nextItem == nil || ![_running isSignaled]) {
            break;
        }

        // If all callbacks have finished and could not immediately push new data
        // then need to reset the audio queues.
        if (_forceRestart || _flush) {
            NSLog(@"Waiting for buffers to return");
            while ([_bufferPool size] < _numAudioBuffers - 1) { // we have 1 buffer already.
                [NSThread sleepForTimeInterval:0.01];
            }
            NSLog(@"Buffers returned");

            OSStatus result = AudioQueueFlush(_audioQueue);
            [self handleResultOsStatus:result description:@"Flushing the audio output queue"];
            _flush = false;

            [self waitForQueueToFill];

            if (_forceRestart) {
                [self stopPlayback:false];
                _forceRestart = false;
            }
        }

        // Ensure playback is running.
        [self startPlayback:false];

        // Extract value.
        AudioQueueBufferRef audioQueueBuffer;
        [_bufferVal getValue:&audioQueueBuffer];

        // Push the data into audio queues.
        [self playSoundData:nextItem withBuffer:audioQueueBuffer];
    }

    [_soundQueueThreadTerminated signalAll];
}

- (void)outputThreadEntryPoint:var {
    [_outputThreadTerminated clear];

    OSStatus result = AudioQueueNewOutput(_audioDescription, HandleOutputBuffer, (__bridge void *) (self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_audioQueue);
    HandleResultOSStatus(result, @"Initializing speaker queue", true);

    result = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, _magicCookie, _magicCookieSize);
    HandleResultOSStatus(result, @"Setting magic cookie for output", true);

    for (int i = 0; i < _numAudioBuffers; i++) {
        result = AudioQueueAllocateBufferWithPacketDescriptions(_audioQueue,
                _bufferSizeBytes,
                1,
                &_audioBuffers[i]);
        HandleResultOSStatus(result, @"Initializing speaker buffer", true);

        [self returnToPool:_audioBuffers[i]];
    }

    NSLog(@"Initialized speaker thread");
    [_queueSetup signalAll];

    _outputThreadRunLoop = CFRunLoopGetCurrent();
    CFRunLoopRun();

    result = AudioQueueDispose(_audioQueue, false);
    HandleResultOSStatus(result, @"Disposing of speaker queue", true);

    [_outputThreadTerminated signalAll];
    NSLog(@"Speaker thread exiting");
}


- (void)initialize {
    @synchronized(self) {
        if (![_running signalAll]) {
            return;
        }

        [_bufferPool clear];

        // Run send operations in a ; run loop (and thread) because we wait for packets to
        // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
        // receive operations) if there were some.
        _outputThread = [[NSThread alloc] initWithTarget:self
                                                selector:@selector(outputThreadEntryPoint:)
                                                  object:nil];
        [_outputThread setName:@"AudioOutput RunLoop"];
        [_outputThread start];
        [_queueSetup wait];
        NSLog(@"Speaker thread initialized");

        _soundQueueThread = [[NSThread alloc] initWithTarget:self selector:@selector(soundQueueThreadEntryPoint:) object:nil];
        [_soundQueueThread setName:@"AudioOutput BufferController"];
        [_soundQueueThread start];
    }
}

// a further call to initialize can revoke this.
- (void)terminate {
    // synchronize on running because stopPlayback is called from the thread _soundQueueThread,
    // and stopPlayback synchronizes on this object (self).
    @synchronized(_running) {
        if (![_running clear]) {
            return;
        }

        // Force thread to exit.
        // This also pauses the queue, preventing new additions.
        [_soundQueue add:nil];

        // Wait for _soundQueueThread to terminate in response to _running being false.
        [_soundQueueThreadTerminated wait];

        CFRunLoopStop(_outputThreadRunLoop);
        [_outputThreadTerminated wait];

        // Allow new additions to the queue.
        [_soundQueue restartQueue];

        // Ensure playback is resumed properly later on.
        [_isPlaying clear];
    }
}

// If currently initialized, reinitialize
// If not currently initialized, do nothing.
- (void)reinitialize {
    @synchronized (_running) {
        if ([_running isSignaled]) {
            [self terminate];
            [self initialize];
        }
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    //NSLog(@"New packet received");
    // Make sure you don't hold onto this reference, only valid for this callback.
    ByteBuffer *copy = [[ByteBuffer alloc] initFromByteBuffer:packet];
    uint qSize = [_soundQueue add:copy];
    if (qSize > 1) {
        [_averageTracker addValue:qSize];
        double qAverageSize = [_averageTracker getWeightedAverage];

        uint estimatedDelay = (uint) (qAverageSize * ((float) ESTIMATED_BUFFER_SIZE_MS));
        //NSLog(@"Q rate = %d, averaged = %.3f, estimated delay required for video = %d", qSize, qAverageSize, estimatedDelay);
        [_mediaDelayDelegate onMediaDelayNotified:estimatedDelay];
    }
}

- (bool)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones]) {
            return true;
        }
    }
    return false;
}

// If the user changes the audio output device they are using.
// Will be called on initialization automatically by iOS.
- (void)audioRouteChangeListenerCallback:(NSNotification *)notification {
    NSDictionary *interruptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interruptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    NSLog(@"Audio route changed, with reason: %d", routeChangeReason);
    [self updateNoiseCancellation];
}

- (void)selectSpeaker {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;

    // Use the device's loud speaker if no headphones are plugged in.
    // Without this, will use the quiet speaker if available, e.g. on iphone this is for taking calls privately.
    bool result = [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    if (!result) {
        NSLog(@"Failed to enable AVAudioSessionCategoryOptionDefaultToSpeaker mode: %@", [error localizedDescription]);
    }
}

// Enable noise cancellation to prevent echo if output is through speakers, otherwise disable it because
// it has the side effect of reducing the volume of audio output.
- (void)updateNoiseCancellation {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    NSString *desiredMode;
    NSString *desiredModeDescription;
    if ([self isHeadsetPluggedIn]) {
        desiredMode = AVAudioSessionModeDefault;
        desiredModeDescription = @"Disabling noise cancellation";
    } else {
        desiredMode = AVAudioSessionModeVideoChat;
        desiredModeDescription = @"Enabling noise cancellation";
    }

    // Incase callback is called multiple times simultaneously.
    @synchronized(_running) {
        if (![[session mode] isEqualToString:desiredMode]) {
            NSLog(desiredModeDescription);
            bool result = [session setMode:desiredMode error:&error];
            if (!result) {
                NSLog(@"Failed to enable %@ mode, reason: %@", desiredMode, [error localizedDescription]);
            }

            // To pickup the change we need to reinitialize the audio queue.
            [self reinitialize];
        }
    }
}

@end
