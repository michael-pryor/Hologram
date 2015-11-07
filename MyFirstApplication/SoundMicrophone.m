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
@import AudioToolbox;

@implementation SoundMicrophone {
    bool _isRecording;
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef *_audioBuffers;
    //NSMutableDictionary*       _audioToByteBufferMap;
    UInt32 _bufferSizeBytes;
    bool _queueSetup;
    AudioStreamBasicDescription _audioDescription;
    id <NewPacketDelegate> _outputSession;
    NSThread *_inputThread;
    Signal *_outputThreadStartupSignal;
    uint _leftPadding;
    uint _numBuffers;
    Byte * _magicCookie;
    int _magicCookieSize;
    Signal *_magicCookieLoaded;
    Boolean done;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)output numBuffers:(uint)numBuffers leftPadding:(uint)padding secondPerBuffer:(Float64)secondsPerBuffer {
    self = [super init];
    if (self) {
        //_audioToByteBufferMap = [[NSMutableDictionary alloc] init];

        _magicCookie = nil;
        _outputSession = output;

#ifndef PCM
        int propSize = sizeof(_audioDescription);
        memset(&_audioDescription, 0, sizeof(_audioDescription));
        _audioDescription.mFormatID = kAudioFormatMPEG4AAC;
        _audioDescription.mChannelsPerFrame = 1;
        _audioDescription.mSampleRate = 8000.0;
        _audioDescription.mFramesPerPacket = 1024;
        //OSStatus status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &propSize, &_audioDescription);
        //HandleResultOSStatus(status, @"Retrieving audio properties", true);
#else

        // Old school uncompressed below:
        _audioDescription.mFormatID = kAudioFormatLinearPCM;
        _audioDescription.mSampleRate = 8000.0;
        _audioDescription.mChannelsPerFrame = 1; // Mono
        _audioDescription.mBitsPerChannel = 16;
        _audioDescription.mBytesPerPacket =
                _audioDescription.mBytesPerFrame =
                        _audioDescription.mChannelsPerFrame * sizeof(SInt16);
        _audioDescription.mFramesPerPacket = 1;
        _audioDescription.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
#endif

        _outputThreadStartupSignal = [[Signal alloc] initWithFlag:false];
        _magicCookieLoaded = [[Signal alloc] initWithFlag:false];

        _numBuffers = numBuffers;
        _leftPadding = padding;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numBuffers);
        _bufferSizeBytes = calculateBufferSize(&_audioDescription, secondsPerBuffer);
        done = false;
    }
    return self;
}

- (void)dealloc {
    [self stopCapturing];
    OSStatus result = AudioQueueDispose(_audioQueue, true);
    HandleResultOSStatus(result, @"Disposing of microphone queue", true);

    free(_audioBuffers);
    _queueSetup = false;
}

- (void)inputThreadEntryPoint:var {
    OSStatus result = AudioQueueNewInput(&_audioDescription,
            HandleInputBuffer,
            (__bridge void *) (self),
            CFRunLoopGetCurrent(),
            kCFRunLoopCommonModes,
            0, // Reserved, must be 0
            &_audioQueue);

    HandleResultOSStatus(result, @"Initializing microphone queue", true);

    // Allocate.
    for (int i = 0; i < _numBuffers; ++i) {
        result = AudioQueueAllocateBuffer(_audioQueue,
                _bufferSizeBytes,
                &_audioBuffers[i]);
        HandleResultOSStatus(result, @"Allocating microphone buffer", true);

        //ByteBuffer* byteBuffer = [[ByteBuffer alloc] initWithSize:bufferByteSize];
        //[_audioToByteBufferMap setObject:byteBuffer forKey: [NSNumber numberWithInteger:(long)mBuffers[i]]];
    }

    _queueSetup = true;
    _isRecording = false;

    NSLog(@"Microphone thread initialized");
    [_outputThreadStartupSignal signal];


    CFRunLoopRun();
}

- (void)enqueueBuffers {
    // Enqueue.
    for (int i = 0; i<_numBuffers; ++i) {
        OSStatus osResult = AudioQueueEnqueueBuffer(_audioQueue,
                _audioBuffers[i],
                0,
                NULL);

        HandleResultOSStatus(osResult, @"Enqueing initial microphone buffer", true);
    }

}

- (Byte*)getMagicCookie {
    return _magicCookie;
}

- (int)getMagicCookieSize {
    return _magicCookieSize;
}

- (void)initialize {
    // Run send operations in a separate run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _inputThread = [[NSThread alloc] initWithTarget:self
                                           selector:@selector(inputThreadEntryPoint:)
                                             object:nil];
    [_inputThread start];
    [_outputThreadStartupSignal wait];

    [self startCapturing];
    [_magicCookieLoaded wait];
    NSLog(@"Microphone thread started");
}

- (void)setOutputSession:(id <NewPacketDelegate>)output {
    _outputSession = output;
}

- (AudioStreamBasicDescription *)getAudioDescription {
    return &_audioDescription;
}

/*- (void)startCapturing {
    [self performSelector:@selector(doStartCapturing) onThread:_inputThread withObject:self waitUntilDone:true];
}*/

- (void)startCapturing {
    if (!_isRecording && _queueSetup) {
        [self enqueueBuffers];

        OSStatus result = 0;
        do {
            result = AudioQueueStart(_audioQueue, NULL);
            HandleResultOSStatus(result, @"Starting microphone queue", true);
        } while(result != 0);

        _isRecording = true;
    }
 }

- (void)stopCapturingPermanently {
    if (_queueSetup) {
        OSStatus result = AudioQueueStop(_audioQueue, FALSE);
        HandleResultOSStatus(result, @"Stopping microphone queue", true);
        _isRecording = false;
    }
}

- (void)stopCapturing {
    if (_isRecording && _queueSetup) {
        OSStatus result = AudioQueuePause(_audioQueue);
        HandleResultOSStatus(result, @"Pausing microphone queue", true);

        result = AudioQueueReset(_audioQueue);
        HandleResultOSStatus(result, @"Resetting microphone queue", true);

        _isRecording = false;
    }
}

//- (NSMutableDictionary*) getAudioToByteBufferMap {
//return _audioToByteBufferMap;
//}

- (id <NewPacketDelegate>)getOutputSession {
    return _outputSession;
}

- (uint)getLeftPadding {
    return _leftPadding;
}

static void HandleInputBuffer(void *aqData,
        AudioQueueRef inAQ,
        AudioQueueBufferRef inBuffer,
        const AudioTimeStamp *inStartTime,
        UInt32 inNumPackets,
        const AudioStreamPacketDescription *inPacketDesc) {
    SoundMicrophone *obj = (__bridge SoundMicrophone *) (aqData);
    uint leftPadding = [obj getLeftPadding];
    uint size = leftPadding + inBuffer->mAudioDataByteSize;

   // NSLog(@"Microphone AUDIO!!! %d",inBuffer->mAudioDataByteSize);


#ifdef PCM
    if(!obj->done) {
        [obj->_magicCookieLoaded signalAll];
        obj->done = true;
    }
#else
    if (inNumPackets == 0) {
        NSLog(@"0 packets received on audio input callback");
        return;
    }

    if (inPacketDesc[0].mVariableFramesInPacket > 0) {
        NSLog(@"VARIABLE FRAMES!!!");
    }

    if (inNumPackets > 1) {
        NSLog(@"More than one packet");
    }

    if (inPacketDesc[0].mStartOffset > 0) {
        NSLog(@"Start offset");
    }

    if (inPacketDesc[0].mDataByteSize != inBuffer->mAudioDataByteSize) {
        NSLog(@"Byte mismatch");
    }

    if (obj->_magicCookie == nil) {
        UInt32 propertySize;
        OSStatus status = AudioQueueGetPropertySize(obj->_audioQueue, kAudioConverterCompressionMagicCookie, &propertySize);
        HandleResultOSStatus(status, @"Retrieving magic cookie size", true);
        obj->_magicCookieSize = propertySize;

        obj->_magicCookie = (Byte *) malloc(propertySize);
        status = AudioQueueGetProperty(obj->_audioQueue, kAudioQueueProperty_MagicCookie, obj->_magicCookie, &propertySize);
        HandleResultOSStatus(status, @"Retrieving magic cookie", true);

        [obj->_magicCookieLoaded signalAll];
    }
#endif

    if (inBuffer->mAudioDataByteSize > 0) {
        //ByteBuffer* buff = [[obj getAudioToByteBufferMap] objectForKey:[NSNumber numberWithInteger:(long)inBuffer]];
        ByteBuffer *buff = [[ByteBuffer alloc] initWithSize:size];
        memcpy(buff.buffer + leftPadding, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        [buff setUsedSize:size];

        //NSLog(@"Sleeping for a bit...");
        //[NSThread sleepForTimeInterval:1];
        //NSLog(@"Input buffer sent");
        [[obj getOutputSession] onNewPacket:buff fromProtocol:UDP];
    } else {
        NSLog(@"Microphone generated empty buffer");
    }
    OSStatus result = AudioQueueEnqueueBuffer(obj->_audioQueue, inBuffer, 0, NULL);
    HandleResultOSStatus(result, @"Enqueing microphone buffer", false);
}


@end
