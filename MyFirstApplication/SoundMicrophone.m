//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "SoundMicrophone.h"
#import "SoundEncodingShared.h"
#import "Signal.h"
#include <unistd.h>




@implementation SoundMicrophone {
    bool                         _isRecording;
    AudioQueueRef                _audioQueue;
    AudioQueueBufferRef*         _audioBuffers;
    //NSMutableDictionary*       _audioToByteBufferMap;
    UInt32                       _bufferSizeBytes;
    bool                         _queueSetup;
    AudioStreamBasicDescription  _audioDescription;
    id<NewPacketDelegate>        _outputSession;
    NSThread*                    _inputThread;
    Signal*                      _outputThreadStartupSignal;
    uint                         _leftPadding;
    uint                         _numBuffers;
}

- (id) initWithOutputSession:(id<NewPacketDelegate>)output numBuffers:(uint)numBuffers leftPadding:(uint)padding secondPerBuffer:(Float64)secondsPerBuffer {
    self = [super init];
    if(self) {
        //_audioToByteBufferMap = [[NSMutableDictionary alloc] init];
        
        _outputSession = output;

        _audioDescription.mFormatID = kAudioFormatLinearPCM;
        _audioDescription.mSampleRate = 8000.0;
        _audioDescription.mChannelsPerFrame = 1; // Mono
        _audioDescription.mBitsPerChannel = 16;
        _audioDescription.mBytesPerPacket =
        _audioDescription.mBytesPerFrame =
        _audioDescription.mChannelsPerFrame * sizeof(SInt16);
        _audioDescription.mFramesPerPacket = 1;
        _audioDescription.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
        
        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
        
        _numBuffers = numBuffers;
        _leftPadding = padding;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numBuffers);
        _bufferSizeBytes = calculateBufferSize(&_audioDescription, secondsPerBuffer);
    }
    return self;
}

- (void) dealloc {
    [self stopCapturing];
    OSStatus result = AudioQueueDispose(_audioQueue, true);
    HandleResultOSStatus(result, @"Disposing of audio input queue", true);
    
    free(_audioBuffers);
    _queueSetup = false;
}

- (void) inputThreadEntryPoint: var {
    OSStatus result = AudioQueueNewInput(&_audioDescription,
                                         HandleInputBuffer,
                                         (__bridge void *)(self),
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0, // Reserved, must be 0
                                         &_audioQueue);
    
    HandleResultOSStatus(result, @"Initializing audio input queue", true);
    
    for (int i = 0; i < _numBuffers; ++i) {
        result = AudioQueueAllocateBuffer(_audioQueue,
                                          _bufferSizeBytes,
                                          &_audioBuffers[i]);
        HandleResultOSStatus(result, @"Allocating audio input queue buffer", true);
        
        //ByteBuffer* byteBuffer = [[ByteBuffer alloc] initWithSize:bufferByteSize];
        //[_audioToByteBufferMap setObject:byteBuffer forKey: [NSNumber numberWithInteger:(long)mBuffers[i]]];
        
        AudioQueueEnqueueBuffer(_audioQueue,
                                _audioBuffers[i],
                                0,
                                NULL);
        
        HandleResultOSStatus(result, @"Enqueing initial audio input buffer", true);
    }
    
    _queueSetup = true;
    _isRecording = false;

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
    _outputSession = output;
}

- (AudioStreamBasicDescription*) getAudioDescription {
    return &_audioDescription;
}

- (void) startCapturing {
    if(!_isRecording && _queueSetup) {
        OSStatus result = AudioQueueStart(_audioQueue, NULL);
        HandleResultOSStatus(result, @"Starting audio input queue", true);
        _isRecording = true;
    }
}

- (void) stopCapturing {
    if(_isRecording && _queueSetup) {
        OSStatus result = AudioQueueStop(_audioQueue, TRUE);
        HandleResultOSStatus(result, @"Stopping audio input queue", true);
        _isRecording = false;
    }
}

//- (NSMutableDictionary*) getAudioToByteBufferMap {
    //return _audioToByteBufferMap;
//}

- (id<NewPacketDelegate>) getOutputSession {
    return _outputSession;
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
    SoundMicrophone* obj = (__bridge SoundMicrophone *)(aqData);
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
    OSStatus result = AudioQueueEnqueueBuffer(obj->_audioQueue, inBuffer, 0, NULL);
    HandleResultOSStatus(result, @"Enqueing audio input buffer", true);
}


@end
