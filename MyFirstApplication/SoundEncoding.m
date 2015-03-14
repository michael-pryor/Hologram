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
    NSMutableDictionary*         _audioToByteBufferMap;
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    bool                         mIsRunning;
    
    AudioStreamBasicDescription  df;
    id<NewPacketDelegate>        outputSession;
}
- (id) init {
    self = [self initWithOutputSession:nil];
    return self;
}

- (id) initWithOutputSession: (id<NewPacketDelegate>)output {
    self = [super init];
    if(self) {
        _audioToByteBufferMap = [[NSMutableDictionary alloc] init];
        
        outputSession = output;
        df = [self getAudioDescription];
        
        OSStatus result = AudioQueueNewInput(&df,
                           HandleInputBuffer,
                           (__bridge void *)(self),
                           CFRunLoopGetCurrent(), // Use internal thread
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
            
            ByteBuffer* byteBuffer = [[ByteBuffer alloc] initWithSize:bufferByteSize];
            [_audioToByteBufferMap setObject:byteBuffer forKey: [NSNumber numberWithInteger:(long)mBuffers[i]]];
            
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

- (void) setOutputSession: (id<NewPacketDelegate>)output {
    outputSession = output;
}

- (AudioStreamBasicDescription) getAudioDescription {
    AudioStreamBasicDescription dfa;
    dfa.mFormatID = kAudioFormatLinearPCM;
    dfa.mSampleRate = 44100.0;
    dfa.mChannelsPerFrame = 1; // Mono
    dfa.mBitsPerChannel = 16;
    dfa.mBytesPerPacket =
    dfa.mBytesPerFrame =
    dfa.mChannelsPerFrame * sizeof(SInt16);
    dfa.mFramesPerPacket = 1;
    dfa.mFormatFlags = kLinearPCMFormatFlagIsBigEndian
    | kLinearPCMFormatFlagIsSignedInteger
    | kLinearPCMFormatFlagIsPacked;
    return dfa;
}

- (void) dispose {
    mIsRunning = false;
    AudioQueueDispose(mQueue, true);
}

- (void) startCapturing {
    if(!isRecording && mIsRunning) {
        AudioQueueStart(mQueue, NULL);
        isRecording = true;
    }
}

- (void) stopCapturing {
    if(isRecording && mIsRunning) {
        AudioQueueStop(mQueue, TRUE);
        isRecording = false;
    }
}

- (NSMutableDictionary*) getAudioToByteBufferMap {
    return _audioToByteBufferMap;
}

- (id<NewPacketDelegate>) getOutputSession {
    return outputSession;
}

static void HandleInputBuffer(void *aqData,
                              AudioQueueRef inAQ,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc)
{
    SoundEncoding* obj = (__bridge SoundEncoding *)(aqData);
    
    if(inBuffer->mAudioDataByteSize > 0) {
        ByteBuffer* buff = [[obj getAudioToByteBufferMap] objectForKey:[NSNumber numberWithInteger:(long)inBuffer]];
        [buff setMemorySize:inBuffer->mAudioDataByteSize retaining:false];
        memcpy(buff.buffer, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        [buff setUsedSize:inBuffer->mAudioDataByteSize];
    
        NSLog(@"Received some audio data");
        [[obj getOutputSession] onNewPacket:buff fromProtocol:UDP];
    } else {
        NSLog(@"Received empty input buffer");
    }
    OSStatus status = AudioQueueEnqueueBuffer(obj->mQueue,
                            inBuffer,
                            0,
                            NULL);
    NSLog(@"Result of enqueing input buffer: %@", NSStringFromOSStatus(status));
}


@end
