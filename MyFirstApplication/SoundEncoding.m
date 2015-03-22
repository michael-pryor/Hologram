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
    
    Signal*                      _outputThreadStartupSignal;
    
    uint                         _leftPadding;
}

- (id) initWithLeftPadding: (uint)padding {
    self = [self initWithOutputSession:nil andLeftPadding:padding];
    return self;
}

- (id) initWithOutputSession:(id<NewPacketDelegate>)output andLeftPadding:(uint)padding {
    self = [super init];
    if(self) {
        //_audioToByteBufferMap = [[NSMutableDictionary alloc] init];
        
        outputSession = output;
        df = [self getAudioDescription];
        
        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
        
        _leftPadding = padding;
    }
    return self;
}

- (void) inputThreadEntryPoint: var {
    OSStatus result = AudioQueueNewInput(&df,
                                         HandleInputBuffer,
                                         (__bridge void *)(self),
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0, // Reserved, must be 0
                                         &mQueue);
    
    HandleResultOSStatus(result, @"Initializing audio input queue", true);
    
    // A fraction of a second.
    bufferByteSize = 8000;
    
    for (int i = 0; i < kNumberBuffers; ++i) {
        result = AudioQueueAllocateBuffer(mQueue,
                                          bufferByteSize,
                                          &mBuffers[i]);
        HandleResultOSStatus(result, @"Allocating audio input queue buffer", true);
        
        //ByteBuffer* byteBuffer = [[ByteBuffer alloc] initWithSize:bufferByteSize];
        //[_audioToByteBufferMap setObject:byteBuffer forKey: [NSNumber numberWithInteger:(long)mBuffers[i]]];
        
        AudioQueueEnqueueBuffer(mQueue,
                                mBuffers[i],
                                0,
                                NULL);
        
        HandleResultOSStatus(result, @"Enqueing initial audio input buffer", true);
    }
    
    mCurrentPacket = 0;
    mIsRunning = true;
    
    isRecording = false;

    [_outputThreadStartupSignal signal];
    
    CFRunLoopRun();
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
    dfa.mBitsPerChannel = 16;
    dfa.mBytesPerPacket =
    dfa.mBytesPerFrame =
    dfa.mChannelsPerFrame * sizeof(SInt16);
    dfa.mFramesPerPacket = 1;
    dfa.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    return dfa;
}

- (void) dispose {
    mIsRunning = false;
    OSStatus result = AudioQueueDispose(mQueue, true);
    HandleResultOSStatus(result, @"Disposing of audio input queue", true);
}

- (void) startCapturing {
    if(!isRecording && mIsRunning) {
        OSStatus result = AudioQueueStart(mQueue, NULL);
        HandleResultOSStatus(result, @"Starting audio input queue", true);
        isRecording = true;
    }
}

- (void) stopCapturing {
    if(isRecording && mIsRunning) {
        OSStatus result = AudioQueueStop(mQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping audio input queue", true);
        isRecording = false;
    }
}

//- (NSMutableDictionary*) getAudioToByteBufferMap {
    //return _audioToByteBufferMap;
//}

- (id<NewPacketDelegate>) getOutputSession {
    return outputSession;
}

- (uint) getLeftPadding {
    return _leftPadding;
}

static void HandleInputBuffer(void *aqData,
                              AudioQueueRef inAQ,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc)
{
    SoundEncoding* obj = (__bridge SoundEncoding *)(aqData);
    uint leftPadding = [obj getLeftPadding];
    uint size = leftPadding + inBuffer->mAudioDataByteSize;
    
    if(inBuffer->mAudioDataByteSize > 0) {
        //ByteBuffer* buff = [[obj getAudioToByteBufferMap] objectForKey:[NSNumber numberWithInteger:(long)inBuffer]];
        ByteBuffer* buff = [[ByteBuffer alloc] initWithSize:size];
        memcpy(buff.buffer+leftPadding, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        [buff setUsedSize: size];
    
        //NSLog(@"Sleeping for a bit...");
        //[NSThread sleepForTimeInterval:1];
        //NSLog(@"Input buffer sent");
        [[obj getOutputSession] onNewPacket:buff fromProtocol:UDP];
    } else {
        NSLog(@"Received empty input buffer from audio input");
    }
    OSStatus result = AudioQueueEnqueueBuffer(obj->mQueue, inBuffer, 0, NULL);
    HandleResultOSStatus(result, @"Enqueing audio input buffer", true);
}


@end
