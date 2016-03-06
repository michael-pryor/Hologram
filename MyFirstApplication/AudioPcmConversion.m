//
// Created by Michael Pryor on 05/03/2016.
//

#import "AudioPcmConversion.h"
#import "SoundEncodingShared.h"
#import "AudioUnitHelpers.h"
#import "TimedCounterLogging.h"

@implementation AudioPcmConversion {
    AudioStreamBasicDescription _outputAudioFormat;
    AudioStreamBasicDescription _inputAudioFormat;

    BlockingQueue *_audioToBeConvertedQueue;

    NSThread *_conversionThread;
    AudioDataContainer *_inProgressDataContainer;

    id <AudioDataPipeline> _callback;

    uint _numFramesPerOperation;
    bool _isRunning;

    TimedCounterLogging *_pcmConversionInboundCounter;
    TimedCounterLogging *_pcmConversionOutboundCounter;
}

- (id)initWithDescription:(NSString *)humanDescription inputFormat:(AudioStreamBasicDescription)inputFormat outputFormat:(AudioStreamBasicDescription)outputFormat outputFormatEx:(AudioFormatProcessResult)outputFormatEx outputResult:(id <AudioDataPipeline>)callback inboundQueue:(BlockingQueue *)queue {
    self = [super init];
    if (self) {
        NSString *inboundDescription = [NSString stringWithFormat:@"PCM conversion inbound %@", humanDescription];
        NSString *outboundDescription = [NSString stringWithFormat:@"PCM conversion outbound %@", humanDescription];

        _pcmConversionInboundCounter = [[TimedCounterLogging alloc] initWithDescription:inboundDescription];
        _pcmConversionOutboundCounter = [[TimedCounterLogging alloc] initWithDescription:outboundDescription];

        if (queue == nil) {
            _audioToBeConvertedQueue = [[BlockingQueue alloc] initWithName:inboundDescription maxQueueSize:100];
        } else {
            _audioToBeConvertedQueue = queue;
        }

        _inputAudioFormat = inputFormat;
        _outputAudioFormat = outputFormat;
        _isRunning = false;
        _callback = callback;
        _numFramesPerOperation = outputFormatEx.framesPerBuffer;

    }
    return self;
}

- (void)initialize {
    @synchronized (self) {
        _isRunning = true;
        _conversionThread = [[NSThread alloc] initWithTarget:self
                                                    selector:@selector(pcmConversionThreadEntryPoint:)
                                                      object:nil];
        [_conversionThread setName:@"Audio PCM Conversion"];
        [_conversionThread start];
    }
}

- (void)terminate {
    @synchronized (self) {
        _isRunning = false;
        [_audioToBeConvertedQueue shutdown];
    }
}

- (void)reset {
    [_audioToBeConvertedQueue clear];
}

// Converting PCM to PCM (different sample rate).
OSStatus pullPcmDataToBeConverted(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioPcmConversion *audioCompression = (__bridge AudioPcmConversion *) inUserData;

    AudioDataContainer *item = [audioCompression getItemToBeConverted];
    do {
        if (item == nil) {
            return kAudioConverterErr_UnspecifiedError;
        }
    } while (![item isValid]);

    // Normally 1 frame per packet.
    *ioNumberDataPackets = item.numFrames / audioCompression->_inputAudioFormat.mFramesPerPacket;

    AudioBufferList *sourceAudioBufferList = [item audioList];

    // Validation.
    if (ioData->mNumberBuffers > sourceAudioBufferList->mNumberBuffers) {
        NSLog(@"Problem, more source buffers than destination");
        return kAudioConverterErr_UnspecifiedError;
    }

    if (outDataPacketDescription != NULL) {
        NSLog(@"outDataPacketDescription is not NULL, unexpected");
        return kAudioConverterErr_UnspecifiedError;
    }

    // Maintain reference to prevent cleanup while buffers are being used.
    if (audioCompression->_inProgressDataContainer != nil) {
        [audioCompression->_inProgressDataContainer freeMemory];
    }
    audioCompression->_inProgressDataContainer = item;

    // Point compression engine to the PCM data.
    bool success = shallowCopyBuffers(ioData, sourceAudioBufferList);
    if (!success) {
        return kAudioConverterErr_UnspecifiedError;
    }

    return noErr;
}


- (void)pcmConversionThreadEntryPoint:var {
    AudioConverterRef audioConverter;

    OSStatus status = AudioConverterNew(&_inputAudioFormat, &_outputAudioFormat, &audioConverter);
    [self validateResult:status description:@"setting up PCM audio converter"];

    AudioBufferList audioBufferList = initializeAudioBufferList();
    AudioBufferList audioBufferListStartState = initializeAudioBufferList();

    const UInt32 numFrames = _numFramesPerOperation;
    allocateBuffersToAudioBufferListEx(&audioBufferList, 1, numFrames * _outputAudioFormat.mBytesPerFrame, 1, 1, true);
    shallowCopyBuffersEx(&audioBufferListStartState, &audioBufferList, ABL_BUFFER_NULL_OUT); // store original state, namely mBuffers[n].mDataByteSize.

    while (_isRunning) {
        @autoreleasepool {
            UInt32 numFramesResult = numFrames;

            status = AudioConverterFillComplexBuffer(audioConverter, pullPcmDataToBeConverted, (__bridge void *) self, &numFramesResult, &audioBufferList, NULL);
            [self validateResult:status description:@"converting PCM audio data" logSuccess:false];

            AudioDataContainer *audioData = [[AudioDataContainer alloc] initWithNumFrames:numFramesResult audioList:&audioBufferList];
            [audioData incrementCounter:_pcmConversionOutboundCounter];
            [_callback onNewAudioData:audioData];

            // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
            resetBuffers(&audioBufferList, &audioBufferListStartState);
        }
    }

    status = AudioConverterDispose(audioConverter);
    [self validateResult:status description:@"disposing of PCM audio converter"];
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [audioData incrementCounter:_pcmConversionInboundCounter];
    [_audioToBeConvertedQueue add:audioData];
}

- (AudioDataContainer *)getItemToBeConverted {
    return [_audioToBeConvertedQueue get];
}
@end