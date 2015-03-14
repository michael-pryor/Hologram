//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "SoundEncoding.h"
#import "SoundEncodingShared.h"
#include <unistd.h>

static const int kNumberBuffers = 3;



@implementation SoundEncoding {
    bool isRecording;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef          mBuffers[kNumberBuffers];
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    bool                         mIsRunning;
    
    AudioStreamBasicDescription  df;
}
- (id) init {
    self = [super init];
    if(self) {
        df.mFormatID = kAudioFormatLinearPCM;
        df.mSampleRate = 44100.0;
        df.mChannelsPerFrame = 1; // Mono
        df.mBitsPerChannel = 16;
        df.mBytesPerPacket =
        df.mBytesPerFrame =
        df.mChannelsPerFrame * sizeof(SInt16);
        df.mFramesPerPacket = 1;
        df.mFormatFlags = kLinearPCMFormatFlagIsBigEndian
        | kLinearPCMFormatFlagIsSignedInteger
        | kLinearPCMFormatFlagIsPacked;
        
        OSStatus result = AudioQueueNewInput(&df,
                           HandleInputBuffer,
                           (__bridge void *)(self),
                           NULL, // Use internal thread
                           kCFRunLoopCommonModes,
                           0, // Reserved, must be 0
                           &mQueue);
        
        NSLog(@"Error: %@",NSStringFromOSStatus(result));
        
        // 1/8 second
        bufferByteSize = 24000;
        
        for (int i = 0; i < kNumberBuffers; ++i) {
            AudioQueueAllocateBuffer(mQueue,
                                     bufferByteSize,
                                     &mBuffers[i]);
            
            AudioQueueEnqueueBuffer(mQueue,
                                    mBuffers[i],
                                    0,
                                    NULL);
        }
        
        mCurrentPacket = 0;
        mIsRunning = true;
        
        isRecording = false;

    }
    return self;
}

- (AudioStreamBasicDescription) getAudioDescription {
    return df;
}

- (void) dispose {
    mIsRunning = false;
    AudioQueueDispose(mQueue, true);
}

- (void) startCapturing {
    if(!isRecording && mIsRunning) {
        AudioQueueStart(mQueue, NULL);
    }
}

- (void) stopCapturing {
    if(isRecording && mIsRunning) {
        AudioQueueStop(mQueue, TRUE);
    }
}

static void HandleInputBuffer(void *aqData,
                              AudioQueueRef inAQ,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc)
{
    SoundEncoding* obj = (__bridge SoundEncoding *)(aqData);
    
    NSLog(@"Received some audio data");
    // DO STUFF HERE.
    
    AudioQueueEnqueueBuffer(obj->mQueue,
                            inBuffer,
                            0,
                            NULL);
}


@end
