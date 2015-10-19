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
    bool _queueSetup;
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
    uint _restartPlaybackNumBuffersThreshold;
    uint _maxQueueSize;
    Signal *_outputThreadStartupSignal;
    id <SoundPlaybackDelegate> _soundPlaybackDelegate;
    Byte *_magicCookie;
    int _magicCookieSize;
}


- (id)initWithAudioDescription:(AudioStreamBasicDescription *)description secondsPerBuffer:(Float64)seconds numBuffers:(uint)numBuffers restartPlaybackThreshold:(uint)restartPlayback maxPendingAmount:(uint)maxAmount soundPlaybackDelegate:(id <SoundPlaybackDelegate>)soundPlaybackDelegate {
    self = [super init];
    if (self) {
        if (restartPlayback < _maxQueueSize) {
            [NSException raise:@"Invalid input audio configuration" format:@"Restart playback threshold must be >= maximum queue size"];
        }

        _bufferSizeBytes = calculateBufferSize(description, seconds);
        _numAudioBuffers = numBuffers;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numAudioBuffers);
        _restartPlaybackNumBuffersThreshold = _numAudioBuffers + restartPlayback;
        _maxQueueSize = maxAmount;

        _audioDescription = description;
        _soundQueue = [[BlockingQueue alloc] initWithMaxQueueSize:_numAudioBuffers + _maxQueueSize];
        _bufferPool = [[BlockingQueue alloc] init];

        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];

        _isPlaying = [[Signal alloc] initWithFlag:false];
        _soundPlaybackDelegate = soundPlaybackDelegate;
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
    if (_queueSetup) {
        [self stopPlayback];
        [_soundQueue restartQueue];
        _queueSetup = false;
    }
}

- (void)setMagicCookie:(Byte *)magicCookie size:(int)size {
    _magicCookie = magicCookie;
    _magicCookieSize = size;
}

- (void)playSoundData:(ByteBuffer *)packet withBuffer:(AudioQueueBufferRef)inBuffer {
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
#ifndef PCM
    struct AudioStreamPacketDescription *desc = malloc(sizeof(AudioStreamPacketDescription));
    desc->mDataByteSize = unreadData;
    desc->mStartOffset = 0;
    desc->mVariableFramesInPacket = 0;
    int numDescs = 1;
#else
    struct AudioStreamPacketDescription *desc = nil;
    int numDescs = 0;
#endif

    inBuffer->mAudioDataByteSize = unreadData;
    OSStatus result = 0;

    // Queue buffer.
    result = AudioQueueEnqueueBuffer(_audioQueue,
            inBuffer,
            numDescs, desc
    );
    if (result == ERR_NOT_PLAYING) {
        if ([_isPlaying clear]) {
            NSLog(@"Speaker queue paused by OS, updated flag (AudioQueueEnqueueBuffer)");
        }
    }

    if (!HandleResultOSStatus(result, @"Enqueing speaker buffer", false)) {
        [self returnToPool:inBuffer];
        return;
    }

    // Decode data.
    result = AudioQueuePrime(_audioQueue, 0, NULL);
    if (result == ERR_NOT_PLAYING) {
        if ([_isPlaying clear]) {
            NSLog(@"Speaker queue paused by OS, updated flag (AudioQueuePrime)");
        }
    }

    if (!HandleResultOSStatus(result, @"Priming speaker buffer", false)) {
        [self returnToPool:inBuffer];
        return;
    }
}

// Callback when buffer has finished playing and is ready to be reused.
static void HandleOutputBuffer(void *aqData,
        AudioQueueRef inAQ,
        AudioQueueBufferRef inBuffer) {
    // Return the buffer to the pool so that it can be reused.
    SoundPlayback *obj = (__bridge SoundPlayback *) (aqData);
    [obj returnToPool:inBuffer];
}

- (void)startPlayback {
    if (_queueSetup) {
        // Start the queue.
        OSStatus result = 0;
        do {
            result = AudioQueueStart(_audioQueue, NULL);
            HandleResultOSStatus(result, @"Starting speaker queue", true);
        } while (result != 0);

        [_soundPlaybackDelegate playbackStarted];
    }
}

- (void)stopPlayback {
    if (_queueSetup) {
        NSLog(@"Pausing speaker queue");
        OSStatus result = AudioQueueStop(_audioQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping speaker queue", true);
        [_soundPlaybackDelegate playbackStopped];
    }
}

// Thread polls on sound queue and plays data.
- (void)soundQueueThreadEntryPoint:var {
    while (true) {
        // Wait for a new item to play.
        ByteBuffer *nextItem = [_soundQueue get];
        if (nextItem == nil) {
            break;
        }

        // Wait for an available audio buffer.
        NSValue *_bufferVal = [_bufferPool get];
        if (_bufferVal == nil) {
            break;
        }

        AudioQueueBufferRef audioQueueBuffer;
        [_bufferVal getValue:&audioQueueBuffer];

        // Push the data into audio queues.
        [self playSoundData:nextItem withBuffer:audioQueueBuffer];
    }
}

- (void)outputThreadEntryPoint:var {
    _queueSetup = true;
    OSStatus result = AudioQueueNewOutput(_audioDescription, HandleOutputBuffer, (__bridge void *) (self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_audioQueue);
    HandleResultOSStatus(result, @"Initializing speaker queue", true);

#ifndef PCM
    result = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, _magicCookie, _magicCookieSize);
    HandleResultOSStatus(result, @"Setting magic cookie for output", true);
#endif

    for (int i = 0; i < _numAudioBuffers; i++) {
        result = AudioQueueAllocateBuffer(_audioQueue,
                _bufferSizeBytes,
                &_audioBuffers[i]);
        HandleResultOSStatus(result, @"Initializing speaker buffer", true);

        [self returnToPool:_audioBuffers[i]];
    }

    [self selectSpeaker];

    NSLog(@"Initialized speaker thread");
    [_outputThreadStartupSignal signal];

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
    [_outputThreadStartupSignal wait];
    NSLog(@"Speaker thread initialized");

    _soundQueueThread = [[NSThread alloc] initWithTarget:self selector:@selector(soundQueueThreadEntryPoint:) object:nil];
    [_soundQueueThread start];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
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
