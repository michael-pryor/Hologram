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
    // Thread safe state.
    Signal *_isRecording;
    Signal *_queueSetup;
    Signal *_magicCookieLoaded;

    // Audio queue interactions.
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef *_audioBuffers;
    AudioStreamBasicDescription _audioDescription;

    // Magic cookie.
    Byte *_magicCookie;
    int _magicCookieSize;

    // Callback.
    id <NewPacketDelegate> _outputSession;

    // Thread.
    NSThread *_inputThread;

    // Settings.
    uint _leftPadding;
    uint _numBuffers;
    UInt32 _bufferSizeBytes;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)output numBuffers:(uint)numBuffers leftPadding:(uint)padding {
    self = [super init];
    if (self) {
        _magicCookie = nil;
        _outputSession = output;

        memset(&_audioDescription, 0, sizeof(_audioDescription));
        _audioDescription.mFormatID = kAudioFormatMPEG4AAC;
        _audioDescription.mChannelsPerFrame = 1;
        _audioDescription.mSampleRate = 8000.0;
        _audioDescription.mFramesPerPacket = 1024;

        _queueSetup = [[Signal alloc] initWithFlag:false];
        _isRecording = [[Signal alloc] initWithFlag:false];
        _magicCookieLoaded = [[Signal alloc] initWithFlag:false];

        _numBuffers = numBuffers;
        _leftPadding = padding;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numBuffers);
        _bufferSizeBytes = calculateBufferSize(&_audioDescription);
    }
    return self;
}

- (void)dealloc {
    [self stopCapturing];
    OSStatus result = AudioQueueDispose(_audioQueue, true);
    HandleResultOSStatus(result, @"Disposing of microphone queue", true);

    free(_audioBuffers);
    [_queueSetup clear];
}

- (bool)shouldAttemptEnqueue {
    return [_isRecording isSignaled] && [_queueSetup isSignaled];
}

- (bool)handleResultOsStatus:(OSStatus)result description:(NSString *)description {
    if (HandleResultOSStatus(result, description, true)) {
        return true;
    }

    [self stopCapturing];
    return false;
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
    }

    NSLog(@"Microphone thread initialized");
    [_queueSetup signalAll];

    CFRunLoopRun();
}

- (void)enqueueBuffer:(AudioQueueBufferRef)buffer {
    OSStatus result;
    int counter = 0;
    do {
        result = AudioQueueEnqueueBuffer(_audioQueue,
                buffer,
                0,
                NULL);
        counter++;
        if (counter == 1000) {
            break;
        }
    }
    while (!HandleResultOSStatus(result, @"Enqueing microphone buffer", false) && [self shouldAttemptEnqueue]);
    if (counter == 1000) {
        NSLog(@"Catestrophic failure of audio input, attempting to restart microphone");
        [self stopCapturing];
        [self startCapturing];
    }
}

- (void)enqueueBuffers {
    for (int i = 0; i < _numBuffers; ++i) {
        [self enqueueBuffer:_audioBuffers[i]];
    }
}

- (Byte *)getMagicCookie {
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
    [_queueSetup wait];

    [self startCapturing];
    NSLog(@"Microphone thread started");
}

- (void)setOutputSession:(id <NewPacketDelegate>)output {
    _outputSession = output;
}

- (AudioStreamBasicDescription *)getAudioDescription {
    return &_audioDescription;
}

- (void)startCapturing {
    if ([_queueSetup isSignaled] && [_isRecording signalAll]) {
        [self enqueueBuffers];

        OSStatus result = AudioQueueStart(_audioQueue, NULL);
        if (![self handleResultOsStatus:result description:@"Starting microphone queue"]) {
            return;
        }

        [_magicCookieLoaded wait];
    }
}

- (void)stopCapturingPermanently {
    if ([_queueSetup clear]) {
        OSStatus result = AudioQueueStop(_audioQueue, FALSE);
        HandleResultOSStatus(result, @"Stopping microphone queue", true);
        [_isRecording clear];
    }
}

- (void)stopCapturing {
    if ([_queueSetup isSignaled] && [_isRecording clear]) {
        OSStatus result = AudioQueuePause(_audioQueue);
        HandleResultOSStatus(result, @"Pausing microphone queue", true);

        result = AudioQueueReset(_audioQueue);
        HandleResultOSStatus(result, @"Resetting microphone queue", true);
    }
}

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

    if (inNumPackets == 0) {
        NSLog(@"0 packets received on audio input callback");
        return;
    }

    if (inPacketDesc[0].mVariableFramesInPacket > 0) {
        NSLog(@"Variable frames");
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
        if (![obj handleResultOsStatus:status description:@"Retrieving magic cookie size"]) {
            [obj->_magicCookieLoaded dummySignalAll];
            return;
        }
        obj->_magicCookieSize = propertySize;

        obj->_magicCookie = (Byte *) malloc(propertySize);
        status = AudioQueueGetProperty(obj->_audioQueue, kAudioQueueProperty_MagicCookie, obj->_magicCookie, &propertySize);
        if (![obj handleResultOsStatus:status description:@"Retrieving magic cookie"]) {
            [obj->_magicCookieLoaded dummySignalAll];
            return;
        }

        [obj->_magicCookieLoaded signalAll];
    }

    if (inBuffer->mAudioDataByteSize > 0) {
        ByteBuffer *buff = [[ByteBuffer alloc] initWithSize:size];
        memcpy(buff.buffer + leftPadding, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        [buff setUsedSize:size];

        [[obj getOutputSession] onNewPacket:buff fromProtocol:UDP];
    } else {
        NSLog(@"Microphone generated empty buffer");
    }

    if ([obj shouldAttemptEnqueue]) {
        [obj enqueueBuffer:inBuffer];
    }
}


@end
