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

@implementation SoundPlayback {
    AudioStreamBasicDescription *_audioDescription;
    AudioQueueRef _audioQueue;
    Signal *_isPlaying;
    BlockingQueue *_soundQueue;

    // Buffers which were returned to the pool.
    // because there was nothing ready in _soundQueue.
    BlockingQueue *_bufferPool;

    // Thread blocks on the sound queue and pushes data out to the output thread.
    NSThread *_soundQueueThread;
    NSThread *_outputThread;

    uint _numAudioBuffers;
    AudioQueueBufferRef *_audioBuffers;
    uint _bufferSizeBytes;
    uint _maxQueueSize;
    Signal *_queueSetup;
    id <SoundPlaybackDelegate> _soundPlaybackDelegate;
    id <MediaDelayNotifier> _mediaDelayDelegate;

    Byte *_magicCookie;
    int _magicCookieSize;

    volatile uint _currentBatchId, _currentBatchIdEnded;

    volatile bool _forceRestart;
    volatile bool _flush;

    volatile int _qSizeTracker;

    AverageTracker *_averageTracker;
}


- (id)initWithAudioDescription:(AudioStreamBasicDescription *)description numBuffers:(uint)numBuffers maxPendingAmount:(uint)maxAmount soundPlaybackDelegate:(id <SoundPlaybackDelegate>)soundPlaybackDelegate mediaDelayDelegate:(id <MediaDelayNotifier>)mediaDelayDelegate {
    self = [super init];
    if (self) {
        _bufferSizeBytes = calculateBufferSize(description);
        _numAudioBuffers = numBuffers;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numAudioBuffers);
        _maxQueueSize = maxAmount;
        _qSizeTracker = 0;

        _audioDescription = description;
        _soundQueue = [[BlockingQueue alloc] initWithMaxQueueSize:_maxQueueSize];
        [_soundQueue setupEventTracker:0.007];
        _bufferPool = [[BlockingQueue alloc] init];

        _queueSetup = [[Signal alloc] initWithFlag:false];

        _isPlaying = [[Signal alloc] initWithFlag:false];
        _soundPlaybackDelegate = soundPlaybackDelegate;

        _mediaDelayDelegate = mediaDelayDelegate;

        _currentBatchId = 0;
        _currentBatchIdEnded = 0;

        // 10 second rolling average.
        _averageTracker = [[AverageTracker alloc] initWithExpiry:60*5];

        _forceRestart = false;
        _flush = false;
    }
    return self;
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
        [self stopPlayback];
        [_soundQueue restartQueue];
    }
}

- (void)setMagicCookie:(Byte *)magicCookie size:(int)size {
    _magicCookie = magicCookie;
    _magicCookieSize = size;
}

- (void)playSoundData:(ByteBuffer *)packet withBuffer:(AudioQueueBufferRef)inBuffer {
    if (![self shouldAttemptEnqueue]) {
        return;
    }

    [packet setCursorPosition:8];
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

    uint batchId = [MediaShared getBatchIdFromByteBuffer:packet];
    inBuffer->mUserData = (void *) batchId;


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

        int numBuffersInUse = [self getBuffersInUse];
        int pendingSize = [_soundQueue size];
        int additionalDelay = pendingSize * 6;
       // NSLog(@"Machine time: %llu, host time %llu, diff %llu (%llums), is in future: %d, buffersInUse: %d, pending size: %d, additional delay: %dms", currentMachineTime, audioBufferStartTime, diff, diffMs, isInFuture, numBuffersInUse, pendingSize, additionalDelay);

        //if (batchId != _currentBatchId) {
        //    _currentBatchId = batchId;
           // NSLog(@"Batch ID %d played", batchId);
            //[_mediaDelayDelegate onMediaDelayNotified:batchId delayMs:diffMs + additionalDelay];
        //}
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
        // Don't return buffer, it has been enqueued so will hit the callback even if failure occurs here.
        return;
    }
}

- (int)getBuffersInUse {
    return _numAudioBuffers - [_bufferPool size];
}

- (bool)handleResultOsStatus:(OSStatus)result description:(NSString *)description {
    if (HandleResultOSStatus(result, description, false)) {
        return true;
    }

    [self stopPlayback];
    return false;
}

// Callback when buffer has finished playing and is ready to be reused.
static void HandleOutputBuffer(void *aqData,
        AudioQueueRef inAQ,
        AudioQueueBufferRef inBuffer) {
    SoundPlayback *obj = (__bridge SoundPlayback *) (aqData);

    uint batchId = (uint) inBuffer->mUserData;
   // NSLog(@"Audio buffer with batch ID of %d returned", batchId);

   // if (batchId != obj->_currentBatchIdEnded) {
       // NSLog(@"Batch ID %d ENDED", batchId);
        obj->_currentBatchIdEnded = batchId;
        //[_mediaDelayDelegate onMediaDelayNotified:batchId delayMs:diffMs + additionalDelay];
    //}

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
    if ([_queueSetup isSignaled] && [_isPlaying signalAll]) {
        OSStatus result = AudioQueueStart(_audioQueue, NULL);
        HandleResultOSStatus(result, @"Starting speaker queue", true);

        [_soundPlaybackDelegate playbackStarted];
    }
}

- (void)stopPlayback {
    if ([_queueSetup isSignaled] && [_isPlaying clear]) {
        OSStatus result = AudioQueueStop(_audioQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping speaker queue", true);
        [_soundPlaybackDelegate playbackStopped];
    }
}

- (void)waitForQueueToFill {
    while ([_soundQueue size] < 3) {
        NSLog(@"Waiting for playback queue to expand");
        [NSThread sleepForTimeInterval:0.01];
    }
}

// Thread polls on sound queue and plays data.
- (void)soundQueueThreadEntryPoint:var {
    [self waitForQueueToFill];

    bool hasPlayedYet = false;
    while (true) {
        // Wait for an available audio buffer.
        NSValue *_bufferVal = [_bufferPool get];
        if (_bufferVal == nil) {
            break;
        }

        // Wait for a new item to play.
        ByteBuffer *nextItem = [_soundQueue get];
        if (nextItem == nil) {
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
                [self stopPlayback];
                _forceRestart = false;
            }
        }

        // Ensure playback is running.
        [self startPlayback];

        // Extract value.
        AudioQueueBufferRef audioQueueBuffer;
        [_bufferVal getValue:&audioQueueBuffer];

        // Push the data into audio queues.
        [self playSoundData:nextItem withBuffer:audioQueueBuffer];
        hasPlayedYet = true;
    }
}

- (void)outputThreadEntryPoint:var {
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

    [self selectSpeaker];

    NSLog(@"Initialized speaker thread");
    [_queueSetup signalAll];

    CFRunLoopRun();

    NSLog(@"Speaker thread exiting");
}


- (void)initialize {
    // Run send operations in a ; run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _outputThread = [[NSThread alloc] initWithTarget:self
                                            selector:@selector(outputThreadEntryPoint:)
                                              object:nil];
    [_outputThread start];
    [_queueSetup wait];
    NSLog(@"Speaker thread initialized");

    _soundQueueThread = [[NSThread alloc] initWithTarget:self selector:@selector(soundQueueThreadEntryPoint:) object:nil];
    [_soundQueueThread start];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    //NSLog(@"New packet received");
    // Make sure you don't hold onto this reference, only valid for this callback.
    ByteBuffer *copy = [[ByteBuffer alloc] initFromByteBuffer:packet];
    uint qSize = [_soundQueue add:copy];
    if (qSize > 1) {
        [_averageTracker addValue:qSize];
        double qAverageSize = [_averageTracker getWeightedAverage];

        uint estimatedDelay = (uint)(qAverageSize * 200.0);
        NSLog(@"Q rate = %d, averaged = %.3f, estimated delay required for video = %d", qSize, qAverageSize, estimatedDelay);
    }
}

- (void)selectSpeaker {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    //[session setMode:AVAudioSessionModeVideoChat error:&error];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
}

@end
