//
// Created by Michael Pryor on 17/02/2016.
//

#import "AudioGraph.h"
#import "SoundEncodingShared.h"

#import "AudioCompression.h"
#import "AudioUnitHelpers.h"

@import AVFoundation;

@implementation AudioGraph {
    AudioCompression *_audioCompression;

    AudioBufferList _audioInputAudioBufferList;
    UInt32 _audioInputAudioBufferOriginalSize;

    AudioUnit _audioProducer;
    AUGraph _mainGraph;

    AudioStreamBasicDescription _audioFormat;

    // For handling devices producing different sizes of output i.e. they may produce
    // a different number of frames with each iteration.
    AudioDataContainer *bufferAvailableContainer;
    AudioBuffer bufferAvailable;
    UInt32 amountAvailable;

    bool _loopbackEnabled;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding {
    self = [super init];
    if (self) {
        _loopbackEnabled = outputSession == nil;

        _audioInputAudioBufferList = initializeAudioBufferListSingle(4096, 1);
        _audioInputAudioBufferOriginalSize = _audioInputAudioBufferList.mBuffers[0].mDataByteSize;

        double sampleRate = [self setupAudioSession];
        _audioFormat = [self prepareAudioFormatWithSampleRate:sampleRate];
        _audioCompression = [[AudioCompression alloc] initWithAudioFormat:_audioFormat outputSession:outputSession leftPadding:leftPadding];
        _mainGraph = [self buildIoGraph];

        bufferAvailableContainer = nil;
        amountAvailable = 0; // trigger read from queue immediately.
    }
    return self;
}

- (void)dealloc {
    freeAudioBufferListEx(&_audioInputAudioBufferList, true);
}

- (void)initialize {
    [_audioCompression initialize];
}

static OSStatus audioOutputPullCallback(
        void *inRefCon,
        AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList *ioData
) {
    OSStatus status;

    @autoreleasepool {
        AudioGraph *audioController = (__bridge AudioGraph *) inRefCon;

        // Validation.
        //
        // If there is a mismatch, may get gaps in the audio, which is annoying for the user.
        // Not sure exactly why this happens, but adjusting the sample rate solves.
        if (ioData->mNumberBuffers > 0) {
            size_t estimatedSize = inNumberFrames * audioController->_audioFormat.mBytesPerFrame;
            size_t actualSize = ioData->mBuffers[0].mDataByteSize;
            if (estimatedSize != actualSize) {
                NSLog(@"Mismatch, num frames = %lu, estimated size = %lu, byte size = %lu", inNumberFrames, estimatedSize, actualSize);

                // Fix the number frames so that the audio compression continues to work properly regardless.
                inNumberFrames = actualSize / audioController->_audioFormat.mBytesPerFrame;
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

        {
            AudioBufferList *audioBufferList = [audioController prepareInputAudioBufferList];

            status = AudioUnitRender([audioController getAudioProducer], ioActionFlags, inTimeStamp, 1, inNumberFrames, audioBufferList);
            if (!HandleResultOSStatus(status, @"rendering input audio", false)) {
                NSLog(@"rendering failed, num buffers: %lu, num bytes: %lu, num channels: %lu", audioBufferList->mNumberBuffers, audioBufferList->mBuffers[0].mDataByteSize, audioBufferList->mBuffers[0].mNumberChannels);
            }

            // Compress audio and send to network.
            printAudioBufferList(ioData, @"audio graph");
            [audioController->_audioCompression onNewAudioData:[[AudioDataContainer alloc] initWithNumFrames:inNumberFrames audioList:audioBufferList]];
        }

        {
            AudioBuffer bufferToFill = ioData->mBuffers[0];
            UInt32 amountToFill = bufferToFill.mDataByteSize;

            while (amountToFill > 0) {
                if (audioController->amountAvailable == 0) {
                    // Cleanup old container. Helps ARC.
                    if (audioController->bufferAvailableContainer != nil) {
                        [audioController->bufferAvailableContainer freeMemory];
                    }

                    // Get decompressed data
                    // Data was on network, and then decompressed, and is now ready for PCM consumption.
                    audioController->bufferAvailableContainer = [audioController->_audioCompression getPendingDecompressedData];
                    if (audioController->bufferAvailableContainer == nil) {
                        // Play silence.
                        *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
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

                UInt32 currentPositionFill = bufferToFill.mDataByteSize - amountToFill;
                UInt32 currentPositionAvailable = audioController->bufferAvailable.mDataByteSize - audioController->amountAvailable;

                memcpy(bufferToFill.mData + currentPositionFill, audioController->bufferAvailable.mData + currentPositionAvailable, amountAvailableToUseNow);

                amountToFill -= amountAvailableToUseNow;
                audioController->amountAvailable -= amountAvailableToUseNow;
            }
        }
    }

    return status;
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

- (double)setupAudioSession {
    // Determine sample rate.
    double sampleRate = 44100.0;

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

    result = [mySession setActive:YES
                            error:&audioSessionError];
    if (!result) {
        NSLog(@"Failed to activate audio session, reason: %@", [audioSessionError localizedFailureReason]);
    }

    sampleRate = [mySession sampleRate];
    NSLog(@"Device sample rate is: %.2f", sampleRate);

    // Lower latency.
    double ioBufferDuration = 0.005;
    result = [mySession setPreferredIOBufferDuration:ioBufferDuration
                                               error:&audioSessionError];
    if (!result) {
        NSLog(@"Failed to set buffer duration to %.5f, reason: %@", ioBufferDuration, [audioSessionError localizedFailureReason]);
    }
    return sampleRate;
}

- (void)setAudioFormat:(AudioUnit)audioUnit {
    OSStatus status = AudioUnitSetProperty(audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &_audioFormat,
            sizeof(_audioFormat));
    [self validateResult:status description:@"setting audio format of audio output device"];

    status = AudioUnitSetProperty(audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &_audioFormat,
            sizeof(_audioFormat));
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
            kAudioUnitScope_Input,
            0,                 // output element
            &ioUnitCallbackStructure,
            sizeof(ioUnitCallbackStructure)
    );
    [self validateResult:status description:@"adding audio output pull callback"];
}

- (AUGraph)buildIoGraph {
    AUGraph processingGraph;
    OSStatus status = NewAUGraph(&processingGraph);
    [self validateResult:status description:@"creating graph"];

    AUNode ioNode = [self addIoNodeToGraph:processingGraph];

    status = AUGraphOpen(processingGraph);
    [self validateResult:status description:@"opening graph"];

    AudioUnit ioUnit = [self getAudioUnitFromGraph:processingGraph fromNode:ioNode];

    [self enableInputOnAudioUnit:ioUnit];
    [self setAudioFormat:ioUnit];

    [self setAudioPullCallback:ioUnit];
    _audioProducer = ioUnit;

    status = AUGraphInitialize(processingGraph);
    [self validateResult:status description:@"initializing graph"];

    status = AUGraphStart(processingGraph);
    [self validateResult:status description:@"starting graph"];

    return processingGraph;
}

- (AudioStreamBasicDescription)prepareAudioFormatWithSampleRate:(double)sampleRate {
    AudioStreamBasicDescription audioDescription = {0};

    size_t bytesPerSample = sizeof(AudioUnitSampleType);
    audioDescription.mFormatID = kAudioFormatLinearPCM;
    audioDescription.mFramesPerPacket = 1;    // Always 1 for PCM.
    audioDescription.mChannelsPerFrame = 1;   // mono
    audioDescription.mSampleRate = sampleRate;
    audioDescription.mBitsPerChannel = 8 * bytesPerSample;;
    audioDescription.mBytesPerFrame = bytesPerSample;
    audioDescription.mBytesPerPacket = bytesPerSample;
    audioDescription.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;

    return audioDescription;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    // Can only be one user of compression at a time, in loopback we use it directly skipping the network.
    if (_loopbackEnabled) {
        return;
    }

    [_audioCompression onNewPacket:packet fromProtocol:protocol];
}

@end