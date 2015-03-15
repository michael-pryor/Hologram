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

static const int kNumberBuffers = 3;

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
    Signal*                       _primed;
}


- (id) initWithAudioDescription:(AudioStreamBasicDescription)description {
    self = [super init];
    if(self) {
        _readyToStart = false;
        bufferByteSize = 24000;
        df = description;
        _soundQueue = [[BlockingQueue alloc] init];
        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
        _primed = [[Signal alloc] initWithFlag:false];
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
    return [_soundQueue get];
}

- (void) playSoundData:(ByteBuffer*)packet withBuffer:(AudioQueueBufferRef)inBuffer {
    memcpy(inBuffer->mAudioData, packet.buffer, packet.bufferUsedSize);
    inBuffer->mAudioDataByteSize = [packet bufferUsedSize];
    OSStatus result = AudioQueueEnqueueBuffer ([self getAudioQueue],
                                               inBuffer,
                                               0,
                                               NULL);
    
    NSLog(@"Result of enqueue: %@", NSStringFromOSStatus(result));
    
    result = AudioQueuePrime([self getAudioQueue], 0, NULL);
    NSLog(@"Result of prime: %@", NSStringFromOSStatus(result));
}


static void HandleOutputBuffer (void                *aqData,
                                AudioQueueRef       inAQ,
                                AudioQueueBufferRef inBuffer) {
    NSLog(@"Retrieving sound output...");
    SoundPlayback* obj = (__bridge SoundPlayback *)(aqData);
    
    if (![obj isQueueActive]) {
        return;
    }
    
    ByteBuffer* packet = [obj getSoundPacketToPlay];

    if (packet != nil) {
        [obj playSoundData:packet withBuffer:inBuffer];
    } else {
        NSLog(@"Sound playback thread termination received");
    }
}

- (void) startPlayback {
    if(!_isPlaying && mIsRunning) {
        Float32 gain = 1.0;                                       // 1
        // Optionally, allow user to override gain setting here
        OSStatus result = AudioQueueSetParameter (                                  // 2
                                mQueue,                                        // 3
                                kAudioQueueParam_Volume,                              // 4
                                gain                                                  // 5
                                );
        NSLog(@"Result of setting audio volume: %@", NSStringFromOSStatus(result));
        
        result = AudioQueueStart(mQueue, NULL);
        NSLog(@"Result of AudioQueueStart: %@", NSStringFromOSStatus(result));
        _isPlaying = true;
    }
}

- (void) stopPlayback {
    if(_isPlaying && mIsRunning) {
        AudioQueueStop(mQueue, TRUE);
        _isPlaying = false;
    }
}

- (void) outputThreadEntryPoint: var {
    mIsRunning = true;
    OSStatus result = AudioQueueNewOutput(&df, HandleOutputBuffer, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &mQueue);
    NSLog(@"Output audio result: %@", NSStringFromOSStatus(result));
  
    for (int i = 0; i < kNumberBuffers; i++) {
        result = AudioQueueAllocateBuffer (mQueue,
                                  bufferByteSize,
                                  &mBuffers[i]);
        NSLog(@"Output buffer allocation result: %@", NSStringFromOSStatus(result));
    }
    
    [_outputThreadStartupSignal signal];
    
    int primeCount = 0;
    while(primeCount < kNumberBuffers) {
        ByteBuffer* buffer = [_soundQueue get];
        if(buffer == nil) {
            NSLog(@"Premature termination signal while priming output buffers, sound output thread exiting");
            return;
        }
        
        NSLog(@"Doing initial enqueue of output data with packet sized [%d] and buffer ID [%d]", [buffer bufferUsedSize], primeCount);
        [self playSoundData:buffer withBuffer:mBuffers[primeCount]];
        
        primeCount++;
    }
    [self startPlayback];

    CFRunLoopRun();
    
    NSLog(@"Sound playback thread exiting");
}


- (void) start {
    // Fill our buffers with some random data to get going!
    for(int n = 0;n<256;n++) {
        ByteBuffer* buf = [[ByteBuffer alloc] init];
        [buf setMemorySize:24000 retaining:false];
        for(int i = 0;i<24000 / 4;i++) {
            uint r = rand();
            [buf addUnsignedInteger:r];
        }
        [_soundQueue add:buf];
    }
    
    // Run send operations in a ; run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _outputThread = [[NSThread alloc] initWithTarget:self
                                      selector:@selector(outputThreadEntryPoint:)
                                      object:nil];
    [_outputThread start];
    NSLog(@"Sound playback thread started");
    [_outputThreadStartupSignal wait];
    NSLog(@"Sound playback thread initialized");
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    NSLog(@"Adding packet of size [%d] to sound output queue", [packet bufferUsedSize]);
    [_soundQueue add:packet];
}

@end
