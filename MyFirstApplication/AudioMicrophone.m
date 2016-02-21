//
// Created by Michael Pryor on 17/02/2016.
//

#import "AudioMicrophone.h"
#import "SoundEncodingShared.h"

#import "AudioCompression.h"
@import AVFoundation;

@implementation AudioMicrophone {
    AudioCompression *_audioCompression;

    AudioUnit _audioProducer;
    AUGraph _mainGraph;

    AudioStreamBasicDescription _audioFormat;
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

    AudioMicrophone *audioController = (__bridge AudioMicrophone *) inRefCon;
    /*NSLog(@"We got a pull request from the speaker!, num frames: %u, num buffers: %u", inNumberFrames, ioData->mNumberBuffers);
    for (int n = 0; n < ioData->mNumberBuffers; n++) {
        NSLog(@"Buffer length: %u, num channels: %u", ioData->mBuffers[n].mDataByteSize, ioData->mBuffers[n].mNumberChannels);
    }*/

    // TODO: remove this, and use compression.
    status = AudioUnitRender([audioController getAudioProducer], ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
    HandleResultOSStatus(status, @"rendering input audio direct", false);

    return status;

    [audioController->_audioCompression onNewAudioData:[[AudioDataContainer alloc] initWithNumFrames:inNumberFrames audioList:ioData]];

    AudioDataContainer *pendingData = [audioController->_audioCompression getPendingDecompressedData];
    if (pendingData == nil) {
        // Play silence.
        *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    }

    status = AudioUnitRender([audioController getAudioProducer], ioActionFlags, inTimeStamp, 1, [pendingData numFrames], [pendingData audioList]);
    HandleResultOSStatus(status, @"rendering input audio", false);
    return status;
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
    ioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
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

- (id)init {
    self = [super init];
    if (self) {
        double sampleRate = [self setupAudioSession];
        _audioFormat = [self prepareAudioFormatWithSampleRate:sampleRate];

        _audioCompression = [[AudioCompression alloc] initWithAudioFormat:_audioFormat];

        _mainGraph = [self buildIoGraph];

        NSLog(@"LETS GOGOGOGO");

    }
    return self;
}

@end