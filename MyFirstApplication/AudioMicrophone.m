//
// Created by Michael Pryor on 17/02/2016.
//

#import "AudioMicrophone.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"

@implementation AudioMicrophone {
    BlockingQueue *audioInputQueue;
    AudioUnit ioUnit;
    AUGraph graph;
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

    OSStatus status = AudioUnitRender([audioController getIoUnit], ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
    HandleResultOSStatus(status, @"rendering input audio", false);
    return status;
}

- (AudioUnit)getIoUnit {
    return ioUnit;
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (AUGraph)buildIoGraph {
    AUGraph processingGraph;
    OSStatus status = NewAUGraph(&processingGraph);
    [self validateResult:status description:@"creating graph"];

    // Access speaker (bus 0)
    // Access microphone (bus 1)
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType = kAudioUnitType_Output;
    ioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags = 0;
    ioUnitDescription.componentFlagsMask = 0;

    AUNode ioNode;
    status = AUGraphAddNode(
            processingGraph,
            &ioUnitDescription,
            &ioNode
    );
    [self validateResult:status description:@"adding I/O node"];

    status = AUGraphOpen(processingGraph);
    [self validateResult:status description:@"opening graph"];

    // Obtain a reference to the newly-instantiated I/O unit
    status = AUGraphNodeInfo(
            processingGraph,
            ioNode,
            NULL,
            &ioUnit
    );
    [self validateResult:status description:@"getting I/O node information"];


    // Enable input on microphone.
    int enable = 1;
    status = AudioUnitSetProperty(
            ioUnit,
            kAudioOutputUnitProperty_EnableIO,   // the property key
            kAudioUnitScope_Input,             // the scope to set the property on
            1,                                 // the element to set the property on
            &enable,                         // the property value
            sizeof(enable)
    );
    [self validateResult:status description:@"enabling audio input"];


    AURenderCallbackStruct ioUnitCallbackStructure;
    ioUnitCallbackStructure.inputProc = &audioOutputPullCallback;
    ioUnitCallbackStructure.inputProcRefCon = (__bridge void *) self;

    // Retrieve pull notifications from speaker.
    status = AudioUnitSetProperty(
            ioUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,                 // output element
            &ioUnitCallbackStructure,
            sizeof(ioUnitCallbackStructure)
    );
    [self validateResult:status description:@"adding audio output pull callback"];

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

        graph = [self buildIoGraph];

        NSLog(@"LETS GOGOGOGO");

    }
    return self;
}

@end