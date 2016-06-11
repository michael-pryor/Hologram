//
// Created by Michael Pryor on 17/02/2016.
//

#import "SequenceDecodingPipe.h"
#import "BlockingQueueTemporal.h"
#import "AudioGraph.h"
#import "SoundEncodingShared.h"

#import "AudioCompression.h"
#import "AudioUnitHelpers.h"
#import "Signal.h"
#import "AudioPcmConversion.h"

static OSStatus audioOutputPullCallback(
        void *inRefCon,
        AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList *ioData
);

@interface AudioPcmMicrophoneToTransitConverter : NSObject <AudioDataPipeline>
- (id)initWithAudioCompression:(AudioCompression *)audioCompression queue:(BlockingQueue *)queue compressionEnabled:(bool)compressionEnabled;
@end

@implementation AudioPcmMicrophoneToTransitConverter {
    AudioCompression *_audioCompression;

    BlockingQueue *_queue;
}
- (id)initWithAudioCompression:(AudioCompression *)audioCompression {
    self = [super init];
    if (self) {
        _audioCompression = audioCompression;
    }
    return self;
}

- (id)initWithAudioCompression:(AudioCompression *)audioCompression queue:(BlockingQueue *)queue compressionEnabled:(bool)compressionEnabled {
    if (compressionEnabled) {
        return [self initWithAudioCompression:audioCompression];
    }
    return [self initWithQueue:queue];
}

- (id)initWithQueue:(BlockingQueue *)queue {
    self = [super init];
    if (self) {
        _queue = queue;
    }
    return self;
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    if (_audioCompression != nil) {
        [_audioCompression onNewAudioData:audioData];
    } else if (_queue != nil) {
        [_queue add:audioData];
    }
}

@end

@implementation AudioGraph {
    // We send AAC compress, transit sample rate PCM data here.
    id <NewPacketDelegate> _outputSession;
    uint _leftPadding;

    AudioCompression *_audioCompression;
    AudioPcmConversion *_audioPcmConversionMicrophoneToTransit;
    AudioPcmConversion *_audioPcmConversionTransitToSpeaker;
    BlockingQueue *_pendingOutputToSpeaker;

    AudioBufferList _audioInputAudioBufferList;
    UInt32 _audioInputAudioBufferOriginalSize;

    AudioUnit _ioAudioUnit;

    // PCM audio format of IO device.
    AudioStreamBasicDescription _audioFormatSpeaker;
    struct AudioFormatProcessResult _audioFormatSpeakerEx;

    // Generally will be same as speaker, but just for flexibility.
    AudioStreamBasicDescription _audioFormatMicrophone;
    struct AudioFormatProcessResult _audioFormatMicrophoneEx;

    // PCM audio format for transit over network.
    AudioStreamBasicDescription _audioFormatTransit;
    struct AudioFormatProcessResult _audioFormatTransitEx;

    // For handling devices producing different sizes of output i.e. they may produce
    // a different number of frames with each iteration.
    AudioDataContainer *bufferAvailableContainer;
    AudioBuffer bufferAvailable;
    UInt32 amountAvailable;

    // Testing options.
    bool _loopbackEnabled; // always false in production code.
    bool _aacCompressionEnabled; // always true in production code.

    Signal *_resetFlag;
    Signal *_isRunning;
    Signal *_isRegisteredWithNotificationCentre;

    id <SequenceGapNotification> _sequenceGapNotifier;
    id <TimeInQueueNotification> _timeInQueueNotifier;

    Signal *_syncInProgress;
    dispatch_queue_t _syncGcdQueue;
    Timer *_syncMaxFrequency;

    bool _isInitialized;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding sequenceGapNotifier:(id <SequenceGapNotification>)sequenceGapNotifier timeInQueueNotifier:(id <TimeInQueueNotification>)timeInQueueNotifier {
    self = [super init];
    if (self) {
        // Store options for later.
        _outputSession = outputSession;
        _leftPadding = leftPadding;

        // Determine if test options should be enabled.
        _loopbackEnabled = outputSession == nil;
        const bool enableCompressionInTesting = true;
        if (!_loopbackEnabled) {
            _aacCompressionEnabled = true;
        } else {
            _aacCompressionEnabled = enableCompressionInTesting;
        }

        // Initialize data structures.
        _isInitialized = false;

        _syncGcdQueue = dispatch_queue_create("SyncGcdQueue", NULL);

        _audioCompression = nil;
        _audioPcmConversionMicrophoneToTransit = nil;
        _audioPcmConversionTransitToSpeaker = nil;
        _pendingOutputToSpeaker = buildAudioQueueEx(@"conversion PCM transit to speaker outbound", self, self);

        _audioInputAudioBufferList = initializeAudioBufferListSingle(4096, 1);
        _audioInputAudioBufferOriginalSize = _audioInputAudioBufferList.mBuffers[0].mDataByteSize;

        bufferAvailableContainer = nil;
        amountAvailable = 0; // trigger read from queue immediately.

        _resetFlag = [[Signal alloc] initWithFlag:false];
        _isRunning = [[Signal alloc] initWithFlag:false];
        _isRegisteredWithNotificationCentre = [[Signal alloc] initWithFlag:false];

        _sequenceGapNotifier = sequenceGapNotifier;
        _timeInQueueNotifier = timeInQueueNotifier;

        _syncInProgress = [[Signal alloc] initWithFlag:false];
        _syncMaxFrequency = [[Timer alloc] initWithFrequencySeconds:0.5 firingInitially:true jitterSeconds:2.0];

        [self buildAudioUnit];
    }
    return self;
}

- (void)onSequenceGap:(uint)gapSize fromSender:(id)sender {
    // Replace with self, so that higher level objects can compare sender.
    NSLog(@"Audio queue reset gap of %d detected", gapSize);
    [_sequenceGapNotifier onSequenceGap:gapSize fromSender:self];
}

- (void)dealloc {
    [self stop];
    [self uninitialize];
    freeAudioBufferListEx(&_audioInputAudioBufferList, true);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (AudioStreamBasicDescription)prepareAudioFormatWithSampleRate:(double)sampleRate {
    AudioStreamBasicDescription audioDescription = {0};

    size_t bytesPerSample = sizeof(SInt32);
    audioDescription.mFormatID = kAudioFormatLinearPCM;
    audioDescription.mFramesPerPacket = 1;    // Always 1 for PCM.
    audioDescription.mChannelsPerFrame = 1;   // mono
    audioDescription.mSampleRate = sampleRate;
    audioDescription.mBitsPerChannel = 8 * bytesPerSample;;
    audioDescription.mBytesPerFrame = bytesPerSample;
    audioDescription.mBytesPerPacket = bytesPerSample;

    // Signed integer.
    // Little endian (set by clearing big endian).
    // Packed = sample bits occupy the entire available bits for the channel (instead of being high or low aligned).
    // Non interleaved i.e. separate buffer per channel. We only have one channel so this doesn't matter.
    // No fractional shift.
    audioDescription.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsSignedInteger;

    return audioDescription;
}

- (void)setupAudioSessionAndUpdateAudioFormat {
    const double transitSampleRate = 44100;

    // Sample rate of audio session must match sample rate of ioUnit.
    AudioSessionInteractions *audioSession = [AudioSessionInteractions instance];
    [audioSession setupAudioSessionWithDesiredHardwareSampleRate:transitSampleRate desiredBufferDuration:0.005];

    // Speaker and microphone must match hardware sample rate.
    //
    // There is a converter built into the IO audio unit, but it does not work well
    // when used with AudioUnitRender calls directly. It only works as expected as part of a closed
    // audio graph i.e. not for our use purposes.
    //
    // If the audio sample rates match the hardware then no sample rate conversion needs to be done
    // by the converter, and our AudioUnitRender calls will work as expected.
    const double hardwareSampleRate = [audioSession hardwareSampleRate];
    _audioFormatSpeaker = [self prepareAudioFormatWithSampleRate:hardwareSampleRate];
    _audioFormatMicrophone = [self prepareAudioFormatWithSampleRate:hardwareSampleRate];

    // For transit across the network we need a standardized sample rate. Not all iOS devices
    // will have the same hardware sample rate, and also we would be better off using a
    // lower sample rate in order to use less bandwidth.
    _audioFormatTransit = [self prepareAudioFormatWithSampleRate:transitSampleRate];

    // Extra information deduced from the formats.
    _audioFormatSpeakerEx = [audioSession processAudioFormat:_audioFormatSpeaker];
    _audioFormatMicrophoneEx = [audioSession processAudioFormat:_audioFormatMicrophone];
    _audioFormatTransitEx = [audioSession processAudioFormat:_audioFormatTransit];
}


- (void)setMicrophoneAudioFormat:(AudioStreamBasicDescription *)format speakerAudioFormat:(AudioStreamBasicDescription *)formatSpeaker ofIoAudioUnit:(AudioUnit)audioUnit {
    OSStatus status = AudioUnitSetProperty(audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            format,
            sizeof(AudioStreamBasicDescription));
    [self validateResult:status description:@"setting audio format of audio output device"];

    status = AudioUnitSetProperty(audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            formatSpeaker,
            sizeof(AudioStreamBasicDescription));
    [self validateResult:status description:@"setting audio format of audio input device"];
}

- (void)enableInputOnAudioUnit:(AudioUnit)audioUnit {
    int enable = 1;
    OSStatus status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,   // the property key
            kAudioUnitScope_Input,             // the scope to set the property on
            1,                                 // the element to set the property on
            &enable,                         // the property value
            sizeof(enable)
    );
    [self validateResult:status description:@"enabling audio input"];
}

- (void)setAudioPullCallback:(AudioUnit)audioUnitPulling {
    AURenderCallbackStruct ioUnitCallbackStructure;
    ioUnitCallbackStructure.inputProc = &audioOutputPullCallback;
    ioUnitCallbackStructure.inputProcRefCon = (__bridge void *) self;

    OSStatus status = AudioUnitSetProperty(
            audioUnitPulling,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Output,
            0,                 // output element
            &ioUnitCallbackStructure,
            sizeof(ioUnitCallbackStructure)
    );
    [self validateResult:status description:@"adding audio output pull callback"];
}

// One can change the audio format of an IO unit simply by uninitializing and initializing,
// do not need to rebuild the entire thing as buildAudioUnit does.
- (void)initializeAudioUnit {
    [self setMicrophoneAudioFormat:&_audioFormatMicrophone speakerAudioFormat:&_audioFormatSpeaker ofIoAudioUnit:_ioAudioUnit];

    OSStatus status = AudioUnitInitialize(_ioAudioUnit);
    [self validateResult:status description:@"Initializing audio IO unit"];
}

// Build a complete IO audio unit.
- (void)buildAudioUnit {
    // Access speaker (bus 0)
    // Access microphone (bus 1)
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType = kAudioUnitType_Output;
    ioUnitDescription.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags = 0;
    ioUnitDescription.componentFlagsMask = 0;

    AudioComponent foundIoUnitReference = AudioComponentFindNext(
            NULL,
            &ioUnitDescription
    );
    AudioComponentInstanceNew(
            foundIoUnitReference,
            &_ioAudioUnit
    );

    [self setAudioPullCallback:_ioAudioUnit];
    [self enableInputOnAudioUnit:_ioAudioUnit];
}

- (void)initializeConverters {
    // Prepare converters.
    BlockingQueue *sharedDecompressionOutboundPcmInboundQueue = buildAudioQueue(@"Decompression AAC outbound / PCM conversion inbound transit to speaker", self);
    _audioCompression = [[AudioCompression alloc] initWithUncompressedAudioFormat:_audioFormatTransit uncompressedAudioFormatEx:_audioFormatSpeakerEx outputSession:_outputSession leftPadding:_leftPadding outboundQueue:sharedDecompressionOutboundPcmInboundQueue sequenceGapNotifier:self];
    _audioPcmConversionMicrophoneToTransit = [[AudioPcmConversion alloc] initWithDescription:@"microphone to transit" inputFormat:_audioFormatMicrophone outputFormat:_audioFormatTransit outputFormatEx:_audioFormatTransitEx outputResult:[[AudioPcmMicrophoneToTransitConverter alloc] initWithAudioCompression:_audioCompression queue:sharedDecompressionOutboundPcmInboundQueue compressionEnabled:_aacCompressionEnabled] inboundQueue:nil sequenceGapNotifier:self];
    _audioPcmConversionTransitToSpeaker = [[AudioPcmConversion alloc] initWithDescription:@"transit to speaker" inputFormat:_audioFormatTransit outputFormat:_audioFormatSpeaker outputFormatEx:_audioFormatSpeakerEx outputResult:self inboundQueue:sharedDecompressionOutboundPcmInboundQueue sequenceGapNotifier:self];

    // Start threads.
    [_audioCompression initialize];
    [_audioPcmConversionMicrophoneToTransit initialize];
    [_audioPcmConversionTransitToSpeaker initialize];
}

- (void)initialize {
    @synchronized (self) {
        if (_isInitialized) {
            return;
        }

        _isInitialized = true;
        [self setupAudioSessionAndUpdateAudioFormat];

        // We don't need to reregister.
        if ([_isRegisteredWithNotificationCentre signalAll]) {
            // Register to be notified when microphone is unplugged.
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:)
                                                         name:AVAudioSessionRouteChangeNotification
                                                       object:nil];
        }

        [self initializeConverters];
        [self initializeAudioUnit];
    }
}

- (void)terminateConverters {
    [_audioCompression terminate];
    [_audioPcmConversionMicrophoneToTransit terminate];
    [_audioPcmConversionTransitToSpeaker terminate];
}

- (void)uninitializeAudioUnit {
    OSStatus status = AudioUnitUninitialize(_ioAudioUnit);
    [self validateResult:status description:@"uninitializing IO audio unit"];
}

- (void)uninitialize {
    @synchronized (self) {
        if (!_isInitialized) {
            return;
        }

        _isInitialized = false;
        [self stop];

        [self terminateConverters];
        [self uninitializeAudioUnit];

        [self reset];
    }
}

- (AudioBufferList *)prepareInputAudioBufferList {
    _audioInputAudioBufferList.mBuffers[0].mDataByteSize = _audioInputAudioBufferOriginalSize;
    return &_audioInputAudioBufferList;
}

- (AudioUnit)getAudioProducer {
    return _ioAudioUnit;
}

static OSStatus audioOutputPullCallback(
        void *inRefCon,
        AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList *ioData
) {
    //NSLog(@"(Speaker) Number frames: %lu, mSampleTime: %.4f", inNumberFrames, inTimeStamp->mSampleTime);

    @autoreleasepool {
        AudioGraph *audioController = (__bridge AudioGraph *) inRefCon;

        if ([audioController->_resetFlag clear]) {
            [audioController doReset];
        }

        if (ioData == nil) {
            return kAudioConverterErr_UnspecifiedError;
        }

        // Validation.
        //
        // If there is a mismatch, may get gaps in the audio, which is annoying for the user.
        // Not sure exactly why this happens, but adjusting the sample rate solves.
        if (ioData->mNumberBuffers > 0) {
            size_t estimatedSize = inNumberFrames * audioController->_audioFormatSpeaker.mBytesPerFrame;
            size_t actualSize = ioData->mBuffers[0].mDataByteSize;
            if (estimatedSize != actualSize) {
                NSLog(@"Mismatch, num frames = %u, estimated size = %lu, byte size = %lu", (unsigned int) inNumberFrames, estimatedSize, actualSize);

                // Fix the number frames so that the audio compression continues to work properly regardless.
                inNumberFrames = actualSize / audioController->_audioFormatSpeaker.mBytesPerFrame;
            }
        }

        if (ioData->mNumberBuffers > 1) {
            NSLog(@"Number of buffers is greater than 1, not supported, value is: %u", (unsigned int) ioData->mNumberBuffers);
            return kAudioConverterErr_UnspecifiedError;
        }

        if (inNumberFrames == 0 || ioData->mNumberBuffers == 0) {
            NSLog(@"No data expected, skipping render request");
            return noErr;
        }

        // Get data from microphone and pass it to PCM converter to convert to 8k.
        {
            AudioBufferList *audioBufferList = [audioController prepareInputAudioBufferList];

            OSStatus status = AudioUnitRender([audioController getAudioProducer], ioActionFlags, inTimeStamp, 1, inNumberFrames, audioBufferList);
            if (HandleResultOSStatus(status, @"rendering input audio", false)) {
                // NSLog(@"Successful with %lu frames, size: %lu, sample rate: %.2f", inNumberFrames, audioBufferList->mBuffers[0].mDataByteSize, inTimeStamp->mSampleTime);
                [audioController->_audioPcmConversionMicrophoneToTransit onNewAudioData:[[AudioDataContainer alloc] initWithNumFrames:inNumberFrames audioList:audioBufferList]];
            }

            if (status != noErr) {
                return status;
            }
        }

        // Fill speaker buffer with data.
        {
            AudioBuffer bufferToFill = ioData->mBuffers[0];
            UInt32 amountToFill = bufferToFill.mDataByteSize;

            while (amountToFill > 0) {
                UInt32 currentPositionFill = bufferToFill.mDataByteSize - amountToFill;

                if (audioController->amountAvailable == 0) {
                    // Cleanup old container. Helps ARC.
                    if (audioController->bufferAvailableContainer != nil) {
                        [audioController->bufferAvailableContainer freeMemory];
                    }

                    // Get decompressed data
                    // Data was on network, and then decompressed, and is now ready for PCM consumption.
                    AudioBufferList *audioBufferList = nil;
                    do {
                        audioController->bufferAvailableContainer = [audioController->_pendingOutputToSpeaker getImmediate];
                        if (audioController->bufferAvailableContainer == nil) {
                            // Fill remainder with silence.
                            *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
                            memset(bufferToFill.mData + currentPositionFill, amountToFill, 0);
                            return noErr;
                        }


                        // Validation.
                        audioBufferList = [audioController->bufferAvailableContainer audioList];
                        if (audioBufferList->mNumberBuffers != 1) {
                            NSLog(@"Decompressed audio buffer must have only 1 buffer, actually has: %u", (unsigned int) audioBufferList->mNumberBuffers);
                            return kAudioConverterErr_UnspecifiedError;
                        }

                        // Safety precaution.
                        if (audioBufferList->mBuffers[0].mData == nil || audioBufferList->mBuffers[0].mDataByteSize == 0) {
                            audioBufferList = nil;
                        }
                    } while (audioBufferList == nil);

                    // Load in for processing.
                    audioController->bufferAvailable = audioBufferList->mBuffers[0];
                    audioController->amountAvailable = audioController->bufferAvailable.mDataByteSize;
                }

                // May be larger or smaller than destination buffer.
                // Copy the data in.
                UInt32 amountAvailableToUseNow;
                if (audioController->amountAvailable > amountToFill) {
                    amountAvailableToUseNow = amountToFill;
                } else {
                    amountAvailableToUseNow = audioController->amountAvailable;
                }

                UInt32 currentPositionAvailable = audioController->bufferAvailable.mDataByteSize - audioController->amountAvailable;

                memcpy(bufferToFill.mData + currentPositionFill, audioController->bufferAvailable.mData + currentPositionAvailable, amountAvailableToUseNow);

                amountToFill -= amountAvailableToUseNow;
                audioController->amountAvailable -= amountAvailableToUseNow;
            }
        }
    }

    return noErr;
}

- (bool)start {
    @synchronized (self) {
        if (![_isRunning signalAll]) {
            return false;
        }

        OSStatus status = AudioOutputUnitStart(_ioAudioUnit);
        if (![self validateResult:status description:@"starting graph"]) {
            [_isRunning clear];
            return false;
        }

        return true;
    }
}

- (bool)stop {
    return [self stop:true];
}

- (bool)stop:(bool)external {
    @synchronized (self) {
        if (![_isRunning clear]) {
            return false;
        }

        if (external) {
            [_syncInProgress clear];
        }

        OSStatus status = AudioOutputUnitStop(_ioAudioUnit);
        if (![self validateResult:status description:@"stopping graph"]) {
            [_isRunning signalAll];
            return false;
        }

        [self reset];
        return true;
    }
}

- (bool)isRunning {
    return [_isRunning isSignaled];
}

// Received a packet from the network, need to decompress AAC -> convert PCM transit to speaker -> play through speaker
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (![_isRunning isSignaled]) {
        return;
    }

    // Can only be one user of compression at a time, in loopback we use it directly skipping the network.
    if (_loopbackEnabled) {
        return;
    }

    [_audioCompression onNewPacket:packet fromProtocol:protocol];
}

// Received a packet ready to play through speaker; it has been decompressed and converted to speaker harware format.
- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [_pendingOutputToSpeaker add:audioData];
}

- (void)doReset {
    NSLog(@"Clearing audio queues");
    [_audioCompression reset];
    [_pendingOutputToSpeaker clear];
    [_audioPcmConversionTransitToSpeaker reset];
    [_audioPcmConversionMicrophoneToTransit reset];
}

- (void)reset {
    NSLog(@"Signaling that audio queues should be cleared");
    [_resetFlag signalAll];
}

- (void)audioRouteChangeListenerCallback:(NSNotification *)notification {
    NSDictionary *interruptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interruptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    NSLog(@"Audio route change, with reason: %ld", (long) routeChangeReason);

    if (routeChangeReason != AVAudioSessionRouteChangeReasonNewDeviceAvailable && routeChangeReason != AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        return;
    }

    // Hardware audio format may change when changing audio output device.
    // iPhone 6S is an example of this.
    // AS a result we reinitialize everything using the new format, just in case it has changed.
    [self stop]; // Pause audio.
    [self uninitialize]; // Cleanup all audio, conversion and compression.
    [self reset]; // Empty intermediate queues.
    [self initialize]; // Reinitialize all audio.
    [self start]; // Unpause audio.
}

- (void)onTimeInQueueNotification:(uint)timeInQueueMs {
    if (timeInQueueMs > 100 && [_syncMaxFrequency getState] && [_syncInProgress signalAll]) {

        dispatch_async(_syncGcdQueue, ^{
            [self stop:false];

            // + 20 to enforce 20 second delay, we are screwed if we go over, so 20ms is a good compromise.
            uint timeLagMs = 10;
            if (timeLagMs > timeInQueueMs) {
                return;
            }

            uint adjustedTimeMs = timeInQueueMs - timeLagMs;

            NSLog(@"Pausing speaker for %dms in order to reduce latency", adjustedTimeMs);
            if (_sequenceGapNotifier != nil) {
                [_sequenceGapNotifier onSequenceGap:adjustedTimeMs fromSender:self];
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, adjustedTimeMs * NSEC_PER_MSEC), _syncGcdQueue, ^{
                if (![_syncInProgress clear]) {
                    return;
                }
                [_syncMaxFrequency reset];
                [self start];
            });
        });
    }

    [_timeInQueueNotifier onTimeInQueueNotification:timeInQueueMs];
}

@end