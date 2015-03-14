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
        OSStatus result = AudioQueueStart(mQueue, nil);
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
    //
    for (int i = 0; i < kNumberBuffers; i++) {
        result = AudioQueueAllocateBuffer (mQueue,
                                  bufferByteSize,
                                  &mBuffers[i]);
        NSLog(@"Output buffer allocation result: %@", NSStringFromOSStatus(result));
        
        /*HandleOutputBuffer((__bridge void *)(self),
                           mQueue,
                           mBuffers[i]);*/
    }
    
    while(!_readyToStart) {
    }
    [self startPlayback];
    CFRunLoopRun();
    
    NSLog(@"Sound playback thread exiting");
}

- (id) initWithAudioDescription:(AudioStreamBasicDescription)description {
    self = [super init];
    if(self) {
        _readyToStart = false;
        bufferByteSize = 24000;
        df = description;
        _soundQueue = [[BlockingQueue alloc] init];
        _objInitialPlayCount = 0;

        
        // Run send operations in a seperate run loop (and thread) because we wait for packets to
        // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
        // receive operations) if there were some.
        _outputThread = [[NSThread alloc] initWithTarget:self
                                          selector:@selector(outputThreadEntryPoint:)
                                          object:nil];
        [_outputThread start];
        NSLog(@"Sound playback thread started");
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {

    [_soundQueue add:packet];
    _readyToStart = true;
    if(_objInitialPlayCount < kNumberBuffers) {
        NSLog(@"DOing initial on queue");
        [self playSoundData:packet withBuffer:mBuffers[_objInitialPlayCount]];
        _objInitialPlayCount++;
    }
}

@end
