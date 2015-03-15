//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "SoundEncoding.h"
#import "SoundEncodingShared.h"
#import "Signal.h"
#include <unistd.h>

static const int kNumberBuffers = 1;



@implementation SoundEncoding {
    bool isRecording;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef          mBuffers[kNumberBuffers];
    //NSMutableDictionary*         _audioToByteBufferMap;
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    bool                         mIsRunning;
    
    AudioStreamBasicDescription  df;
    id<NewPacketDelegate>        outputSession;
    NSThread*                    _inputThread;
    
    Signal*                       _outputThreadStartupSignal;
    Signal*                       _primed;
}
- (id) init {
    self = [self initWithOutputSession:nil];
    return self;
}

- (void) inputThreadEntryPoint: var {
    OSStatus result = AudioQueueNewInput(&df,
                                         HandleInputBuffer,
                                         (__bridge void *)(self),
                                         0,
                                         0,
                                         0, // Reserved, must be 0
                                         &mQueue);
    
    NSLog(@"Error: %@",NSStringFromOSStatus(result));
    
    // 1/8 second
    bufferByteSize = 8000;
    
    for (int i = 0; i < kNumberBuffers; ++i) {
        AudioQueueAllocateBuffer(mQueue,
                                 bufferByteSize,
                                 &mBuffers[i]);
        
        //ByteBuffer* byteBuffer = [[ByteBuffer alloc] initWithSize:bufferByteSize];
        //[_audioToByteBufferMap setObject:byteBuffer forKey: [NSNumber numberWithInteger:(long)mBuffers[i]]];
        
        AudioQueueEnqueueBuffer(mQueue,
                                mBuffers[i],
                                0,
                                NULL);
    }
    
    mCurrentPacket = 0;
    mIsRunning = true;
    
    isRecording = false;

    [_outputThreadStartupSignal signal];
    
    CFRunLoopRun();
}

- (id) initWithOutputSession: (id<NewPacketDelegate>)output {
    self = [super init];
    if(self) {
        //_audioToByteBufferMap = [[NSMutableDictionary alloc] init];
        
        outputSession = output;
        df = [self getAudioDescription];
        
        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
        _primed = [[Signal alloc] initWithFlag:false];
    }
    return self;
}

- (void) start {
    // Run send operations in a seperate run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _inputThread = [[NSThread alloc] initWithTarget:self
                                           selector:@selector(inputThreadEntryPoint:)
                                             object:nil];
    [_inputThread start];
    [_outputThreadStartupSignal wait];
    NSLog(@"Sound input thread started");
}

- (void) setOutputSession: (id<NewPacketDelegate>)output {
    outputSession = output;
}

- (AudioStreamBasicDescription) getAudioDescription {
    AudioStreamBasicDescription dfa;
    dfa.mFormatID = kAudioFormatLinearPCM;
    dfa.mSampleRate = 8000.0;
    dfa.mChannelsPerFrame = 1; // Mono
    dfa.mBitsPerChannel = 8;
    dfa.mBytesPerPacket =
    dfa.mBytesPerFrame =
    dfa.mChannelsPerFrame * sizeof(SInt8);
    dfa.mFramesPerPacket = 1;
    dfa.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
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

//- (NSMutableDictionary*) getAudioToByteBufferMap {
    //return _audioToByteBufferMap;
//}

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
        //ByteBuffer* buff = [[obj getAudioToByteBufferMap] objectForKey:[NSNumber numberWithInteger:(long)inBuffer]];
        ByteBuffer* buff = [[ByteBuffer alloc] initWithSize:inBuffer->mAudioDataByteSize];
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
