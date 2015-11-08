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

    Byte *_magicCookie;
    int _magicCookieSize;

    bool _shouldWipeDataQueue;
}


- (id)initWithAudioDescription:(AudioStreamBasicDescription *)description numBuffers:(uint)numBuffers maxPendingAmount:(uint)maxAmount soundPlaybackDelegate:(id <SoundPlaybackDelegate>)soundPlaybackDelegate {
    self = [super init];
    if (self) {
        _bufferSizeBytes = calculateBufferSize(description);
        _numAudioBuffers = numBuffers;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numAudioBuffers);
        _maxQueueSize = maxAmount;

        _audioDescription = description;
        _soundQueue = [[BlockingQueue alloc] initWithMaxQueueSize:_maxQueueSize];
        _bufferPool = [[BlockingQueue alloc] init];

        _queueSetup = [[Signal alloc] initWithFlag:false];

        _isPlaying = [[Signal alloc] initWithFlag:false];
        _soundPlaybackDelegate = soundPlaybackDelegate;

        _shouldWipeDataQueue = true;
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

    // Queue buffer.
    OSStatus result = AudioQueueEnqueueBuffer(_audioQueue,
            inBuffer,
            1,
            desc);
    if (![self handleResultOsStatus:result description:@"Enqueing speaker buffer"]) {
        [self returnToPool:inBuffer];
        return;
    }

    // Decode data.
    result = AudioQueuePrime(_audioQueue, 0, NULL);
    if (![self handleResultOsStatus:result description:@"Priming speaker buffer"]) {
        // Don't return buffer, it has been enqueued so will hit the callback even if failure occurs here.
        return;
    }
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
        if (_shouldWipeDataQueue) {
            [_soundQueue restartQueue];
        }

        OSStatus result = AudioQueueStart(_audioQueue, NULL);
        HandleResultOSStatus(result, @"Starting speaker queue", true);

        [_soundPlaybackDelegate playbackStarted];
    }
}

- (void)stopPlayback:(bool)wipeDataQueue {
    if ([_queueSetup isSignaled] && [_isPlaying clear]) {
        _shouldWipeDataQueue = wipeDataQueue;
        OSStatus result = AudioQueueStop(_audioQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping speaker queue", true);
        [_soundPlaybackDelegate playbackStopped];
    }
}

- (void)stopPlayback {
    [self stopPlayback:true];
}

// Thread polls on sound queue and plays data.
- (void)soundQueueThreadEntryPoint:var {
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
        if ([_bufferPool size] == _numAudioBuffers - 1 && hasPlayedYet) {
            OSStatus result = AudioQueueFlush(_audioQueue);
            [self handleResultOsStatus:result description:@"Flushing the audio output queue"];

            [self stopPlayback:false];
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
    [_soundQueue add:copy];
}

- (void)selectSpeaker {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    //[session setMode:AVAudioSessionModeVideoChat error:&error];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
}

@end
