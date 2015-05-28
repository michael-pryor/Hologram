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
#import "Timer.h"
@import AVFoundation;

@implementation SoundPlayback {
    AudioStreamBasicDescription*  _audioDescription;
    AudioQueueRef                 _audioQueue;
    bool                          _queueSetup;
    Signal*                       _isPlaying;
    BlockingQueue*                _soundQueue;
    NSThread*                     _outputThread;
    uint                          _numAudioBuffers;
    AudioQueueBufferRef*          _audioBuffers;
    uint                          _bufferSizeBytes;
    bool                          _readyToStart;
    uint                          _restartPlaybackNumBuffersThreshold;
    uint                          _maxQueueSize;
    Signal*                       _outputThreadStartupSignal;
    id<SoundPlaybackDelegate>     _soundPlaybackDelegate;
}


- (id)initWithAudioDescription:(AudioStreamBasicDescription*)description secondsPerBuffer:(Float64)seconds numBuffers:(uint)numBuffers restartPlaybackThreshold:(uint)restartPlayback maxPendingAmount:(uint)maxAmount soundPlaybackDelegate:(id<SoundPlaybackDelegate>)soundPlaybackDelegate {
    self = [super init];
    if(self) {
        if(restartPlayback < _maxQueueSize) {
            [NSException raise:@"Invalid input audio configuration" format:@"Restart playback threshold must be >= maximum queue size"];
        }
        
        _readyToStart = false;
        _bufferSizeBytes = calculateBufferSize(description, seconds);
        _numAudioBuffers = numBuffers;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numAudioBuffers);
        _restartPlaybackNumBuffersThreshold = _numAudioBuffers + restartPlayback;
        _maxQueueSize = maxAmount;
        
        _audioDescription = description;
        _soundQueue = [[BlockingQueue alloc] initWithMaxQueueSize:_numAudioBuffers + _maxQueueSize];
        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
        
        _isPlaying = [[Signal alloc] initWithFlag:false];
        _soundPlaybackDelegate = soundPlaybackDelegate;
    }
    return self;
}

- (void)dealloc {
    free(_audioBuffers);
}

- (bool) isQueueActive {
    return _queueSetup;
}

- (AudioQueueRef) getAudioQueue {
    return _audioQueue;
}

- (void) shutdown {
    if(_queueSetup) {
        [self stopPlayback];
        [_soundQueue shutdown];
        _queueSetup = false;
    }
}

- (ByteBuffer*) getSoundPacketToPlay {
    ByteBuffer* result = [_soundQueue getImmediate];
    if(result != nil) {
        return result;
    }
    
    //NSLog(@"Audio output queue paused because no pending data");
    [self stopPlayback];
    return nil;
}

- (void) playSoundData:(ByteBuffer*)packet withBuffer:(AudioQueueBufferRef)inBuffer {
    uint unreadData = packet.getUnreadDataFromCursor;
    if(unreadData > 0) {
        if(unreadData > _bufferSizeBytes) {
            NSLog(@"Incorrectly sized output buffer received, expected [%d], received [%d]", _bufferSizeBytes, unreadData);
            unreadData = _bufferSizeBytes;
        }
        
        memcpy(inBuffer->mAudioData, packet.buffer + packet.cursorPosition, unreadData);
    }
    inBuffer->mAudioDataByteSize = unreadData;
    OSStatus result = AudioQueueEnqueueBuffer ([self getAudioQueue],
                                               inBuffer,
                                               0,
                                               NULL);
    if(result == ERR_NOT_PLAYING) {
        if([_isPlaying clear]) {
            NSLog(@"Audio output queue paused by OS, updated flag (AudioQueueEnqueueBuffer)");
        }
        return;
    }
    HandleResultOSStatus(result, @"Enqueing audio output buffer", true);
    
    result = AudioQueuePrime([self getAudioQueue], 0, NULL);
    if(result == ERR_NOT_PLAYING) {
        if([_isPlaying clear]) {
            NSLog(@"Audio output queue paused by OS, updated flag (AudioQueuePrime)");
        }
        return;
    }
    HandleResultOSStatus(result, @"Priming audio output buffer", true);
}


static void HandleOutputBuffer (void                *aqData,
                                AudioQueueRef       inAQ,
                                AudioQueueBufferRef inBuffer) {
    SoundPlayback* obj = (__bridge SoundPlayback *)(aqData);
    
    if (![obj isQueueActive]) {
        return;
    }
    
    // Latest must be kept low here otherwise sound queue API stops working properly.
    ByteBuffer* packet = [obj getSoundPacketToPlay];
   
    if (packet != nil) {
        [obj playSoundData:packet withBuffer:inBuffer];
    }
}

- (void) startPlayback {
    if(![_isPlaying signal] && _queueSetup && [_soundQueue getPendingAmount] >= _numAudioBuffers) {
        // Start the queue.
        NSLog(@"Starting audio output queue");
        while(true) {
            OSStatus result = AudioQueueStart(_audioQueue, NULL);
            if(result == ERR_NOT_PLAYING) {
                NSLog(@"Audio output queue paused by OS, attempting multiple restarts (AudioQueueStart)");
                [NSThread sleepForTimeInterval:0.01];
                continue;
            }
            if(!HandleResultOSStatus(result, @"Starting audio output queue", true)) {
                break;
            }
        }
        
        // Requeue buffers.
        // Saw a case where blocked forever on get, so changed it to getImmediate.
        // It blocked forever because receiving by UDP starts playback, but queue can only be filled
        // by another UDP packet later on.
        // Not sure why check above did not do the job, i.e. getPendingAmount >= _numAudioBuffers.
        // Perhaps shutdown was called?
        int primeCount = 0;
        while(primeCount < _numAudioBuffers) {
            ByteBuffer* buffer = [_soundQueue getImmediate];
            if(buffer == nil) {
                return;
            }
            
            [self playSoundData:buffer withBuffer:_audioBuffers[primeCount]];
            primeCount++;
        }
        
        [_soundPlaybackDelegate playbackStarted];
    }
}

- (void) stopPlayback {
    if([_isPlaying clear] && _queueSetup) {
        NSLog(@"Pausing audio output queue");
        OSStatus result = AudioQueueStop(_audioQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping audio output queue", true);
        [_soundPlaybackDelegate playbackStopped];
    }
}


- (void) outputThreadEntryPoint: var {
    _queueSetup = true;
    OSStatus result = AudioQueueNewOutput(_audioDescription, HandleOutputBuffer, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_audioQueue);
    HandleResultOSStatus(result, @"Initializing audio output queue", true);
    
    for (int i = 0; i < _numAudioBuffers; i++) {
        result = AudioQueueAllocateBuffer (_audioQueue,
                                           _bufferSizeBytes,
                                           &_audioBuffers[i]);
        HandleResultOSStatus(result, @"Initializing audio output buffer", true);
    }
    
    [self selectSpeaker];
    [_outputThreadStartupSignal signal];

    CFRunLoopRun();
    
    NSLog(@"Sound playback thread exiting");
}


- (void) start {
    // Fill our buffers with some random data to get going!
    for(int n = 0;n<_numAudioBuffers;n++) {
        ByteBuffer* buf = [[ByteBuffer alloc] init];
        [buf setMemorySize:_bufferSizeBytes retaining:false];
        for(int i = 0;i<_bufferSizeBytes-1;i+=sizeof(uint)) {
            uint r = 0;//rand();
            [buf addUnsignedInteger:r];
        }
        [buf setCursorPosition:0];
        [_soundQueue add:buf];
    }
    
    // Run send operations in a ; run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _outputThread = [[NSThread alloc] initWithTarget:self
                                            selector:@selector(outputThreadEntryPoint:)
                                              object:nil];
    [_outputThread start];
    [_outputThreadStartupSignal wait];
    NSLog(@"Sound playback thread initialized");
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    // Make sure you don't hold onto this reference, only valid for this callback.
    ByteBuffer* copy = [[ByteBuffer alloc] initFromByteBuffer:packet];
    [_soundQueue add:copy];
    
    if(![_isPlaying isSignaled] && [_soundQueue getPendingAmount] >= _restartPlaybackNumBuffersThreshold) {
        [self startPlayback];
    }
}

- (void)selectSpeaker {
    AVAudioSession* session = [AVAudioSession sharedInstance];
    NSError* error;
    //[session setMode:AVAudioSessionModeVideoChat error:&error];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
}

@end
