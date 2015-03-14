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
    AudioQueueBufferRef           mBuffers[kNumberBuffers];
    UInt32                        bufferByteSize;
    AudioStreamPacketDescription  *mPacketDescs;
    bool                          mIsRunning;
    BlockingQueue*                _soundQueue;

}

- (bool) isQueueActive {
    return mIsRunning;
}

- (AudioQueueRef) getAudioQueue {
    return mQueue;
}

- (void) shutdown {
    if(mIsRunning) {
        mIsRunning = false;
        [_soundQueue shutdown];
        AudioQueueStop(mQueue, false);
    }
}

- (ByteBuffer*) getSoundPacketToPlay {
    return [_soundQueue get];
}


static void HandleOutputBuffer (void                *aqData,
                                AudioQueueRef       inAQ,
                                AudioQueueBufferRef inBuffer) {
    
    SoundPlayback* obj = (__bridge SoundPlayback *)(aqData);
    
    if (![obj isQueueActive]) {
        return;
    }
    
    ByteBuffer* packet = [obj getSoundPacketToPlay];
    

    if (packet != nil) {
        inBuffer->mAudioDataByteSize = [packet bufferUsedSize];
        AudioQueueEnqueueBuffer ([obj getAudioQueue],
                                 inBuffer,
                                 0,
                                 NULL);
    }
}

- (id) initWithAudioDescription:(AudioStreamBasicDescription)description {
    self = [super init];
    if(self) {
        df = description;
        _soundQueue = [[BlockingQueue alloc] init];
        AudioQueueNewOutput(&df, HandleOutputBuffer, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &mQueue);
        
    }
    return self;
}

@end
