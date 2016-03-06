//
// Created by Michael Pryor on 17/02/2016.
//

#import "AudioGraph.h"
#import "SoundEncodingShared.h"

#import "AudioCompression.h"
#import "AudioUnitHelpers.h"
#import "Signal.h"
#import "AudioPcmConversion.h"
#import "BlockingQueue.h"

@import AVFoundation;

@interface AudioPcmMicrophoneToTransitConverter : NSObject <AudioDataPipeline>

@end

@implementation AudioPcmMicrophoneToTransitConverter {
    AudioCompression *_audioCompression;
}
- (id)initWithAudioCompression:(AudioCompression *)audioCompression {
    self = [super init];
    if (self) {
        _audioCompression = audioCompression;
    }
    return self;
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [_audioCompression onNewAudioData:audioData];
}

@end

@implementation AudioGraph {
    AudioCompression *_audioCompression;
    AudioPcmConversion *_audioPcmConversionMicrophoneToTransit;
    AudioPcmConversion *_audioPcmConversionTransitToSpeaker;
    BlockingQueue *_pendingOutputToSpeaker;

    AudioBufferList _audioInputAudioBufferList;
    UInt32 _audioInputAudioBufferOriginalSize;

    AudioUnit _audioProducer;
    AUGraph _mainGraph;

    // PCM audio format of IO device.
    AudioStreamBasicDescription _audioFormatSpeaker;
    AudioStreamBasicDescription _audioFormatMicrophone;

    // PCM audio format for transit over network.
    AudioStreamBasicDescription _audioFormatTransit;

    // For handling devices producing different sizes of output i.e. they may produce
    // a different number of frames with each iteration.
    AudioDataContainer *bufferAvailableContainer;
    AudioBuffer bufferAvailable;
    UInt32 amountAvailable;

    bool _loopbackEnabled;

    Signal *_resetFlag;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding {
    self = [super init];
    if (self) {
        _loopbackEnabled = outputSession == nil;

        _pendingOutputToSpeaker = [[BlockingQueue alloc] initWithName:@"conversion PCM transit to speaker outbound" maxQueueSize:100000];

        _audioInputAudioBufferList = initializeAudioBufferListSingle(4096, 1);
        _audioInputAudioBufferOriginalSize = _audioInputAudioBufferList.mBuffers[0].mDataByteSize;

        const double transitSampleRate = [self setupAudioSessionAndUpdateAudioFormat];

        BlockingQueue * sharedDecompressionOutboundPcmInboundQueue = [[BlockingQueue alloc] initWithName:@"Decompression AAC outbound" maxQueueSize:100];

        _audioCompression = [[AudioCompression alloc] initWithAudioFormat:_audioFormatSpeaker outputSession:outputSession leftPadding:leftPadding outboundQueue:sharedDecompressionOutboundPcmInboundQueue];

        // Converts 44k (or something like that) PCM sample data from microphone into 8K PCM smaple data (transit format), and passes directly to audio compression to convert to AAC.
        _audioPcmConversionMicrophoneToTransit = [[AudioPcmConversion alloc] initWithDescription:@"microphone to transit" inputFormat:&_audioFormatMicrophone outputFormat:&_audioFormatTransit outputResult:[[AudioPcmMicrophoneToTransitConverter alloc] initWithAudioCompression:_audioCompression] numFramesPerOperation:50 inboundQueue:nil];

        _audioPcmConversionTransitToSpeaker = [[AudioPcmConversion alloc] initWithDescription:@"transit to speaker" inputFormat:&_audioFormatTransit outputFormat:&_audioFormatMicrophone outputResult:self numFramesPerOperation:256 inboundQueue:(BlockingQueue*)sharedDecompressionOutboundPcmInboundQueue];
        _mainGraph = [self buildIoGraphWithTransitSampleRate:transitSampleRate];

        bufferAvailableContainer = nil;
        amountAvailable = 0; // trigger read from queue immediately.

        _resetFlag = [[Signal alloc] initWithFlag:false];
    }
    return self;
}

- (void)dealloc {
    [self stopAudioGraph];
    [self uninitializeAudioGraph];
    freeAudioBufferListEx(&_audioInputAudioBufferList, true);
}

- (double)setupAudioSessionAndUpdateAudioFormat {
    const double transitSampleRate = 8000;

    // Sample rate of audio session must match sample rate of ioUnit.
    const double hardwareSampleRate = [self setupAudioSessionWithDesiredHardwareSampleRate:16000];

    _audioFormatSpeaker = [self prepareAudioFormatWithSampleRate:hardwareSampleRate];
    _audioFormatMicrophone = [self prepareAudioFormatWithSampleRate:hardwareSampleRate];
    _audioFormatTransit = [self prepareAudioFormatWithSampleRate:transitSampleRate];

    return hardwareSampleRate;
}

- (void)initialize {
    [_audioCompression initialize];
    [_audioPcmConversionMicrophoneToTransit initialize];
    [_audioPcmConversionTransitToSpeaker initialize];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];

    [self startAudioGraph];
}


static OSStatus renderNotifyCallback(
        void *inRefCon,
        AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList *ioData
) {
    //  NSLog(@"RENDER NOTIFY (%lu): Number frames: %lu, mSampleTime: %.4f", inBusNumber, inNumberFrames, inTimeStamp->mSampleTime);
    return noErr;
}


- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [_pendingOutputToSpeaker add:audioData];
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
                NSLog(@"Mismatch, num frames = %lu, estimated size = %lu, byte size = %lu", inNumberFrames, estimatedSize, actualSize);

                // Fix the number frames so that the audio compression continues to work properly regardless.
                inNumberFrames = actualSize / audioController->_audioFormatSpeaker.mBytesPerFrame;
            }
        }

        if (ioData->mNumberBuffers > 1) {
            NSLog(@"Number of buffers is greater than 1, not supported, value is: %lu", ioData->mNumberBuffers);
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
                NSLog(@"Successful with %lu frames, size: %lu, sample rate: %.2f", inNumberFrames, audioBufferList->mBuffers[0].mDataByteSize, inTimeStamp->mSampleTime);
                [audioController->_audioPcmConversionMicrophoneToTransit onNewAudioData:[[AudioDataContainer alloc] initWithNumFrames:inNumberFrames audioList:audioBufferList]];
            }

            if (status != noErr) {
                return status;
            }
        }

        // Convert PCM from 8k transit to speaker format.
       /* {
            AudioDataContainer *pendingPcmConversion = nil;
            while (true) {
                pendingPcmConversion = [audioController->_audioCompression getPendingDecompressedData];
                if (pendingPcmConversion != nil) {
                    [audioController->_audioPcmConversionTransitToSpeaker onNewAudioData:pendingPcmConversion];
                } else {
                    break;
                }
            }
        }*/

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
                    audioController->bufferAvailableContainer = [audioController->_pendingOutputToSpeaker getImmediate];
                    if (audioController->bufferAvailableContainer == nil) {
                        // Fill remainder with silence.
                        *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
                        memset(bufferToFill.mData + currentPositionFill, amountToFill, 0);
                        return noErr;
                    }


                    // Validation.
                    AudioBufferList *audioBufferList = [audioController->bufferAvailableContainer audioList];
                    if (audioBufferList->mNumberBuffers != 1) {
                        NSLog(@"Decompressed audio buffer must have only 1 buffer, actually has: %lu", audioBufferList->mNumberBuffers);
                        return kAudioConverterErr_UnspecifiedError;
                    }

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

- (AudioBufferList *)prepareInputAudioBufferList {
    _audioInputAudioBufferList.mBuffers[0].mDataByteSize = _audioInputAudioBufferOriginalSize;
    return &_audioInputAudioBufferList;
}

- (AudioUnit)getAudioProducer {
    return _audioProducer;
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (AUNode)addIoNodeToGraph:(AUGraph)graph {
    // Access speaker (bus 0)
    // Access microphone (bus 1)
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType = kAudioUnitType_Output;
    ioUnitDescription.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags = 0;
    ioUnitDescription.componentFlagsMask = 0;

    AUNode ioNode;
    OSStatus status = AUGraphAddNode(
            graph,
            &ioUnitDescription,
            &ioNode
    );
    [self validateResult:status description:@"adding I/O node"];
    return ioNode;
};

- (AudioUnit)getAudioUnitFromGraph:(AUGraph)graph fromNode:(AUNode)node {
    AudioUnit audioUnit;

    // Obtain a reference to the newly-instantiated I/O unit
    OSStatus status = AUGraphNodeInfo(
            graph,
            node,
            NULL,
            &audioUnit
    );
    [self validateResult:status description:@"getting audio node information"];
    return audioUnit;
}

- (double)setupAudioSessionWithDesiredHardwareSampleRate:(double)sampleRate {
    NSError *audioSessionError = nil;
    AVAudioSession *mySession = [AVAudioSession sharedInstance];
    BOOL result = [mySession setPreferredSampleRate:sampleRate
                                              error:&audioSessionError];
    if (!result) {
        NSLog(@"Preferred sample rate of %.2f not allowed, reason: %@", sampleRate, [audioSessionError localizedFailureReason]);
    }

    // Use the device's loud speaker if no headphones are plugged in.
    // Without this, will use the quiet speaker if available, e.g. on iphone this is for taking calls privately.
    NSError *error;
    result = [mySession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    if (!result) {
        NSLog(@"Failed to enable AVAudioSessionCategoryOptionDefaultToSpeaker mode: %@", [error localizedDescription]);
    }

    result = [mySession setMode:AVAudioSessionModeVideoChat error:&error];
    if (!result) {
        NSLog(@"Failed to enable AVAudioSessionModeVideoChat mode, reason: %@", [error localizedDescription]);
    }

    // Lower latency.
    double ioBufferDuration = 0.005;
    result = [mySession setPreferredIOBufferDuration:ioBufferDuration
                                               error:&audioSessionError];
    if (!result) {
        NSLog(@"Failed to set buffer duration to %.5f, reason: %@", ioBufferDuration, [audioSessionError localizedFailureReason]);
    }

    result = [mySession setActive:YES
                            error:&audioSessionError];
    if (!result) {
        NSLog(@"Failed to activate audio session, reason: %@", [audioSessionError localizedFailureReason]);
    }

    double actualSampleRate = [mySession sampleRate];
    NSLog(@"Device sample rate is: %.2f", actualSampleRate);

    return actualSampleRate;
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

- (AUGraph)buildIoGraphWithTransitSampleRate:(double)sampleRate {
    AUGraph processingGraph;
    OSStatus status = NewAUGraph(&processingGraph);
    [self validateResult:status description:@"creating graph"];

    AUNode ioNode = [self addIoNodeToGraph:processingGraph];

    status = AUGraphOpen(processingGraph);
    [self validateResult:status description:@"opening graph"];

    AudioUnit ioUnit = [self getAudioUnitFromGraph:processingGraph fromNode:ioNode];

    _audioFormatMicrophone.mSampleRate = sampleRate;
    _audioFormatSpeaker.mSampleRate = sampleRate;

    [self setMicrophoneAudioFormat:&_audioFormatMicrophone speakerAudioFormat:&_audioFormatSpeaker ofIoAudioUnit:ioUnit];

    [self setAudioPullCallback:ioUnit];
    /*status = AUGraphConnectNodeInput (
            processingGraph,
            ioNode,           // source node
            1,  // source node bus
            ioNode,              // destination node
            0  // desinatation node element
    );
    [self validateResult:status description:@"connecting microphone to speaker"];*/

    status = AudioUnitAddRenderNotify(ioUnit, renderNotifyCallback, nil);
    [self validateResult:status description:@"adding render notify to microphone"];

    [self enableInputOnAudioUnit:ioUnit];
    _audioProducer = ioUnit;

    /* UInt32 framesPerSliceIn = 4096*3;
     status = AudioUnitSetProperty(  microphonePcmConverterAudioUnit,
             kAudioUnitProperty_MaximumFramesPerSlice,
             kAudioUnitScope_Global,
             0,
             &framesPerSliceIn,
             sizeof(UInt32));
     [self validateResult:status description:@"setting frames per slice of microphone PCM converter"];

     status = AudioUnitSetProperty(  speakerPcmConverterAudioUnit,
             kAudioUnitProperty_MaximumFramesPerSlice,
             kAudioUnitScope_Global,
             0,
             &framesPerSliceIn,
             sizeof(UInt32));
     [self validateResult:status description:@"setting frames per slice of speaker PCM converter"];

     UInt32 framesPerSlice;
     UInt32 framesPerSliceSize = sizeof(framesPerSlice);
     status = AudioUnitGetProperty(  microphonePcmConverterAudioUnit,
             kAudioUnitProperty_MaximumFramesPerSlice,
             kAudioUnitScope_Global,
             0,
             &framesPerSlice,
             &framesPerSliceSize);
     [self validateResult:status description:@"getting frames per slice of microphone PCM converter"];
 */

    status = AUGraphInitialize(processingGraph);
    [self validateResult:status description:@"initializing graph"];


    return processingGraph;
}

- (void)startAudioGraph {
    [self logAudioSessionInformation];

    OSStatus status = AUGraphStart(_mainGraph);
    [self validateResult:status description:@"starting graph"];
}

- (void)stopAudioGraph {
    while ([self isRunning]) {
        OSStatus status = AUGraphStop(_mainGraph);
        [self validateResult:status description:@"stopping graph"];
    }

    [self reset];
}

- (bool)isRunning {
    Boolean isRunning;
    OSStatus status = AUGraphIsRunning(_mainGraph, &isRunning);
    [self validateResult:status description:@"determining whether graph is running" logSuccess:false];
    return isRunning;
}

- (void)uninitializeAudioGraph {
    OSStatus status;

    status = AUGraphClearConnections(_mainGraph);
    [self validateResult:status description:@"clearing connections"];

    status = AUGraphUninitialize(_mainGraph);
    [self validateResult:status description:@"uninitializing graph"];

    status = AUGraphClose(_mainGraph);
    [self validateResult:status description:@"closing graph"];

    status = DisposeAUGraph(_mainGraph);
    [self validateResult:status description:@"disposing graph"];
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

    // Unsigned integer.
    // Little endian.
    // Packed = sample bits occupy the entire available bits for the channel (instead of being high or low aligned).
    // Non interleaves i.e. separate buffer per channel.
    // No fractional shift.
    audioDescription.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsSignedInteger;

    return audioDescription;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (![self isRunning]) {
        return;
    }

    // Can only be one user of compression at a time, in loopback we use it directly skipping the network.
    if (_loopbackEnabled) {
        return;
    }

    [_audioCompression onNewPacket:packet fromProtocol:protocol];
}

- (void)logAudioSessionInformation {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *route = [session currentRoute];
    NSArray<AVAudioSessionPortDescription *> *inputs = [route inputs];
    NSArray<AVAudioSessionPortDescription *> *outputs = [route outputs];

    NSLog(@"%d inputs, %d outputs", [inputs count], [outputs count]);
    for (AVAudioSessionPortDescription *input in inputs) {
        NSLog(@"Input: %@", input);
    }

    for (AVAudioSessionPortDescription *output in outputs) {
        NSLog(@"Output: %@", output);
    }

    NSLog(@"Category: %@, options %u", [session category], [session categoryOptions]);
    NSLog(@"Sample rate: %lf, options %lf", [session sampleRate], [session IOBufferDuration]);

    NSLog(@"Input number channels: %i, output number channels: %i", [session inputNumberOfChannels], [session outputNumberOfChannels]);

    NSLog(@"Other audio playing: %i", [session isOtherAudioPlaying]);
}


- (void)doReset {
    NSLog(@"Clearing audio queues");
    [_audioCompression reset];
}

- (void)reset {
    NSLog(@"Signaling that audio queues should be cleared");
    [_resetFlag signalAll];
}

- (void)audioRouteChangeListenerCallback:(NSNotification *)notification {
    NSDictionary *interruptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interruptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    NSLog(@"Audio route change, with reason: %d", routeChangeReason);

    if (routeChangeReason != AVAudioSessionRouteChangeReasonNewDeviceAvailable && routeChangeReason != AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        return;
    }

    // Pause audio graph.
    [self stopAudioGraph];

    // Empty intermediate buffers.
    /* OSStatus status = AudioUnitReset(_audioProducer, kAudioUnitScope_Global, 0);
     [self validateResult:status description:@"resetting audio unit"];*/

    // Empty intermediate queues.
    [self reset];

    // Reconfigure AVAudioSession.
    NSError *error;
    BOOL result = [[AVAudioSession sharedInstance] setActive:false error:&error];
    if (!result) {
        NSLog(@"Failed to terminate AVAudioSession, reason: %@", error);
        return;
    }

    [self uninitializeAudioGraph];

    const double transitSampleRate = [self setupAudioSessionAndUpdateAudioFormat];
    _mainGraph = [self buildIoGraphWithTransitSampleRate:transitSampleRate];

    // Reconfigure IO unit.
    // Sample rate may have changed.
    /* status = AudioUnitUninitialize(_audioProducer);
     [self validateResult:status description:@"Uninitializing audio IO unit"];

     [self setupAudioSessionAndUpdateAudioFormat];
     [self setMicrophoneAudioFormat:&_audioFormat speakerAudioFormat:&_audioFormatTransit ofIoAudioUnit:_audioProducer];

     // Reinitialize.
     status = AudioUnitInitialize(_audioProducer);
     [self validateResult:status description:@"Initializing audio IO unit"];*/

    // Start audio graph again.
    [self startAudioGraph];
}

@end