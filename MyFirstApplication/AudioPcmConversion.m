//
// Created by Michael Pryor on 05/03/2016.
//

#import "AudioPcmConversion.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"
#import "AudioUnitHelpers.h"

@implementation AudioPcmConversion {
    AudioStreamBasicDescription _outputAudioFormat;
    AudioStreamBasicDescription _inputAudioFormat;

    BlockingQueue *_audioToBeConvertedQueue;

    NSThread *_conversionThread;
    AudioDataContainer *_inProgressDataContainer;

    id <AudioDataPipeline> _callback;

    uint _numFramesPerOperation;
    bool _isRunning;

    TimedCounter *_pcmConversionInboundCounter;
    TimedCounter *_pcmConversionOutboundCounter;

    NSString * _humanDescription;
    NSString * _inboundDescription;
    NSString *_outboundDescription;
}

- (id)initWithDescription:(NSString*)humanDescription inputFormat:(AudioStreamBasicDescription *)inputFormat outputFormat:(AudioStreamBasicDescription *)outputFormat outputResult:(id <AudioDataPipeline>)callback numFramesPerOperation:(UInt32)numFrames inboundQueue:(BlockingQueue*)queue{
    self = [super init];
    if (self) {
        _humanDescription = humanDescription;
        _inboundDescription = [NSString stringWithFormat:@"PCM conversion inbound %@", _humanDescription];
        _outboundDescription = [NSString stringWithFormat:@"PCM conversion outbound %@", _humanDescription];

        const uint freqSeconds = 60;
        _pcmConversionInboundCounter = [[TimedCounter alloc] initWithTimer:[[Timer alloc] initWithFrequencySeconds:freqSeconds firingInitially:false]];
        _pcmConversionOutboundCounter = [[TimedCounter alloc] initWithTimer:[[Timer alloc] initWithFrequencySeconds:freqSeconds firingInitially:false]];

        if (queue == nil) {
            _audioToBeConvertedQueue = [[BlockingQueue alloc] initWithName:_inboundDescription maxQueueSize:100];
        } else {
            _audioToBeConvertedQueue = queue;
        }

        _inputAudioFormat = *inputFormat;
        _outputAudioFormat = *outputFormat;
        _isRunning = false;
        _callback = callback;
        _numFramesPerOperation = numFrames;

    }
    return self;
}

- (void)initialize {
    _isRunning = true;
    _conversionThread = [[NSThread alloc] initWithTarget:self
                                                selector:@selector(pcmConversionThreadEntryPoint:)
                                                  object:nil];
    [_conversionThread setName:@"Audio PCM Conversion"];
    [_conversionThread start];
}


// Converting PCM to PCM (different sample rate).
OSStatus pullPcmDataToBeConverted(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioPcmConversion *audioCompression = (__bridge AudioPcmConversion *) inUserData;

    AudioDataContainer *item = [audioCompression getItemToBeConverted];
    if (item == nil) {
        return kAudioConverterErr_UnspecifiedError;
    }

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

    printAudioBufferList(ioData, @"PCM conversion callback");
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

            AudioDataContainer *container = [[AudioDataContainer alloc] initWithNumFrames:numFramesResult audioList:&audioBufferList];
            [AudioDataContainer handleTimedCounter:_pcmConversionOutboundCounter description:_outboundDescription incrementContainer:container];
            [_callback onNewAudioData:container];

            // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
            resetBuffers(&audioBufferList, &audioBufferListStartState);
        }
    }
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [AudioDataContainer handleTimedCounter:_pcmConversionInboundCounter description:_inboundDescription incrementContainer:audioData];
    [_audioToBeConvertedQueue add:audioData];
}

- (AudioDataContainer *)getItemToBeConverted {
    return [_audioToBeConvertedQueue get];
}
@end