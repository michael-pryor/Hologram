//
// Created by Michael Pryor on 17/02/2016.
//

#import "AudioMicrophone.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"

@implementation AudioMicrophone {
    BlockingQueue *audioInputQueue;
    AudioUnit audioProducer;
    AUGraph mainGraph;
}

static OSStatus audioOutputPullCallback(
        void *inRefCon,
        AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList *ioData
) {
    AudioMicrophone *audioController = (__bridge AudioMicrophone *) inRefCon;
    NSLog(@"We got a pull request from the speaker!");

    OSStatus status = AudioUnitRender([audioController getAudioProducer], ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
    HandleResultOSStatus(status, @"rendering input audio", false);
    return status;
}

- (AudioUnit)getAudioProducer {
    return audioProducer;
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (AUNode) addIoNodeToGraph:(AUGraph)graph {
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

- (AUNode) addAudioConverterNodeToGraph:(AUGraph)graph {
    AudioComponentDescription convertUnitDescription;
    convertUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    convertUnitDescription.componentType          = kAudioUnitType_FormatConverter;
    convertUnitDescription.componentSubType       = kAudioUnitSubType_AUConverter;
    convertUnitDescription.componentFlags         = 0;
    convertUnitDescription.componentFlagsMask     = 0;

    AUNode audioConverter;
    OSStatus status = AUGraphAddNode(
            graph,
            &convertUnitDescription,
            &audioConverter
    );
    [self validateResult:status description:@"adding converter node"];
    return audioConverter;
}

- (AudioUnit) getAudioUnitFromGraph:(AUGraph)graph fromNode:(AUNode)node {
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

- (void)setAudioPullCallback:(AudioUnit)ioAudioUnit {
    AURenderCallbackStruct ioUnitCallbackStructure;
    ioUnitCallbackStructure.inputProc = &audioOutputPullCallback;
    ioUnitCallbackStructure.inputProcRefCon = (__bridge void *) self;

    OSStatus status = AudioUnitSetProperty(
            ioAudioUnit,
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

    [self setAudioPullCallback:ioUnit];
    audioProducer = ioUnit;


    status = AUGraphInitialize(processingGraph);
    [self validateResult:status description:@"initializing graph"];

    status = AUGraphStart(processingGraph);
    [self validateResult:status description:@"starting graph"];

    return processingGraph;
}

- (id)init {
    self = [super init];
    if (self) {
        audioInputQueue = [[BlockingQueue alloc] init];

        mainGraph = [self buildIoGraph];

        NSLog(@"LETS GOGOGOGO");

    }
    return self;
}

@end