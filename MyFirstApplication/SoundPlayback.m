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

static const int kNumberBuffers = 1;
static const int restartPlaybackThreshold = kNumberBuffers + 1;
static const int maxQueueSize = 2;

@implementation SoundPlayback {
    AudioStreamBasicDescription   df;
    AudioQueueRef                 mQueue;
    bool                          mIsRunning;
    bool                          _isPlaying;
    BlockingQueue*                _soundQueue;
    NSThread*                     _outputThread;
    AudioQueueBufferRef           mBuffers[kNumberBuffers];
    int                           bufferByteSize;
    bool                          _readyToStart;
    int                           _objInitialPlayCount;
    
    Signal*                       _outputThreadStartupSignal;
}


- (id) initWithAudioDescription:(AudioStreamBasicDescription)description {
    self = [super init];
    if(self) {
        _readyToStart = false;
        bufferByteSize = 8000;
        df = description;
        _soundQueue = [[BlockingQueue alloc] initWithMaxQueueSize:maxQueueSize];
        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
    }
    return self;
}

- (bool) isQueueActive {
    return mIsRunning;
}

- (AudioQueueRef) getAudioQueue {
    return mQueue;
}

- (void) shutdown {
    if(mIsRunning) {
        [self stopPlayback];
        mIsRunning = false;
        [_soundQueue shutdown];
        AudioQueueStop(mQueue, false);
    }
}

- (ByteBuffer*) getSoundPacketToPlay {
    ByteBuffer* result = [_soundQueue getImmediate];
    if(result != nil) {
        return result;
    }
    
    NSLog(@"Audio output queue paused because no pending data");
    [self stopPlayback];
    return nil;
}

- (void) playSoundData:(ByteBuffer*)packet withBuffer:(AudioQueueBufferRef)inBuffer {
    if(packet.getUnreadDataFromCursor > 0) {
        memcpy(inBuffer->mAudioData, packet.buffer + packet.cursorPosition, packet.getUnreadDataFromCursor);
    }
    inBuffer->mAudioDataByteSize = [packet getUnreadDataFromCursor];
    OSStatus result = AudioQueueEnqueueBuffer ([self getAudioQueue],
                                               inBuffer,
                                               0,
                                               NULL);
    if(result == ERR_NOT_PLAYING) {
        NSLog(@"Audio output queue paused by OS, updating flags (AudioQueueEnqueueBuffer)");
        _isPlaying = false;
        return;
    }
    HandleResultOSStatus(result, @"Enqueing audio output buffer", true);
    
    result = AudioQueuePrime([self getAudioQueue], 0, NULL);
    if(result == ERR_NOT_PLAYING) {
        NSLog(@"Audio output queue paused by OS, updating flags (AudioQueuePrime)");
        _isPlaying = false;
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
    if(!_isPlaying && mIsRunning && [_soundQueue getPendingAmount] >= kNumberBuffers) {
        // Start the queue.
        NSLog(@"Starting audio output queue");
        while(true) {
            OSStatus result = AudioQueueStart(mQueue, NULL);
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
        int primeCount = 0;
        while(primeCount < kNumberBuffers) {
            ByteBuffer* buffer = [_soundQueue get];
            if(buffer == nil) {
                NSLog(@"Premature termination signal while priming output buffers, sound output thread exiting");
                return;
            }
            
            [self playSoundData:buffer withBuffer:mBuffers[primeCount]];
            primeCount++;
        }

        _isPlaying = true;
    }
}

- (void) stopPlayback {
    if(_isPlaying && mIsRunning) {
        OSStatus result = AudioQueueStop(mQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping audio output queue", true);
        _isPlaying = false;
    }
}


- (void) outputThreadEntryPoint: var {
    mIsRunning = true;
    OSStatus result = AudioQueueNewOutput(&df, HandleOutputBuffer, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &mQueue);
    HandleResultOSStatus(result, @"Initializing audio output queue", true);
    
    for (int i = 0; i < kNumberBuffers; i++) {
        result = AudioQueueAllocateBuffer (mQueue,
                                           bufferByteSize,
                                           &mBuffers[i]);
        HandleResultOSStatus(result, @"Initializing audio output buffer", true);
    }
    
    [self selectSpeaker];
    [_outputThreadStartupSignal signal];

    CFRunLoopRun();
    
    NSLog(@"Sound playback thread exiting");
}


- (void) start {
    // Fill our buffers with some random data to get going!
    for(int n = 0;n<kNumberBuffers;n++) {
        ByteBuffer* buf = [[ByteBuffer alloc] init];
        [buf setMemorySize:bufferByteSize retaining:false];
        for(int i = 0;i<bufferByteSize-1;i+=sizeof(uint)) {
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
    
    if(!_isPlaying && [_soundQueue getPendingAmount] >= restartPlaybackThreshold) {
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
