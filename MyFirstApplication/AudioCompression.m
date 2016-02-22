//
// Created by Michael Pryor on 21/02/2016.
//

#import "AudioCompression.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"
#import "AudioUnitHelpers.h"

@implementation AudioDataContainer
- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList {
    self = [super init];
    if (self) {
        _numFrames = numFrames;
        _audioList = cloneAudioBufferList(audioList);
        printAudioBufferList(_audioList, @"container init");
    }
    return self;
}

- (void)freeMemory {
    freeAudioBufferList(_audioList);
    _audioList = NULL;
}

- (void)dealloc {
    [self freeMemory];
}
@end


@implementation AudioCompression {
    // Audio input (microphone) --> audioToBeCompressedQueue --> [compression] --> [network] --> audioToBeDecompressedQueue --> [decompression] --> audioToBeOutputQueue
    BlockingQueue *_audioToBeCompressedQueue;

    BlockingQueue *_audioToBeDecompressedQueue;

    BlockingQueue *_audioToBeOutputQueue;

    AudioConverterRef _audioConverter;

    NSThread *_compressionThread;

    AudioStreamBasicDescription _compressedAudioFormat;
    AudioStreamBasicDescription _uncompressedAudioFormat;

    // We keep a reference to this to prevent it being cleaned up while the data is being compressed.
    // Documentation states we must not cleanup between callbacks, but during next cleanup can cleanup,
    // which means that it is sufficient to maintain one reference here.
    AudioDataContainer * _uncompressedAudioDataContainer;
}

- (id)initWithAudioFormat:(AudioStreamBasicDescription)uncompressedAudioFormat {
    self = [super init];
    if (self) {
        _uncompressedAudioDataContainer = nil;
        
        _audioToBeCompressedQueue = [[BlockingQueue alloc] initWithMaxQueueSize:30];
        _audioToBeDecompressedQueue = [[BlockingQueue alloc] initWithMaxQueueSize:30];
        _audioToBeOutputQueue = [[BlockingQueue alloc] initWithMaxQueueSize:30];

        _uncompressedAudioFormat = uncompressedAudioFormat;

        AudioStreamBasicDescription compressedAudioDescription = {0};
        compressedAudioDescription.mFormatID = kAudioFormatMPEG4AAC;
        compressedAudioDescription.mChannelsPerFrame = 1;
        compressedAudioDescription.mSampleRate = 32000.0;
        compressedAudioDescription.mFramesPerPacket = 1024;
        compressedAudioDescription.mFormatFlags = 0;
        _compressedAudioFormat = compressedAudioDescription;
    }
    return self;
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer {
    static AudioClassDescription desc;

    UInt32 encoderSpecifier = type;
    OSStatus st;

    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
            sizeof(encoderSpecifier),
            &encoderSpecifier,
            &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int) (st));
        return nil;
    }

    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
            sizeof(encoderSpecifier),
            &encoderSpecifier,
            &size,
            descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int) (st));
        return nil;
    }

    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
                (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }

    return nil;
}

- (void)initialize {
    _compressionThread = [[NSThread alloc] initWithTarget:self
                                                 selector:@selector(compressionThreadEntryPoint:)
                                                   object:nil];
    [_compressionThread setName:@"Audio Compression"];
    [_compressionThread start];
}

// Converting PCM to AAC.
OSStatus pullUncompressedDataToAudioConverter(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioCompression *audioCompression = (__bridge AudioCompression *) inUserData;

    AudioDataContainer *item = [audioCompression getUncompressedItem];

    // Normally 1 frame per packet.
    *ioNumberDataPackets = item.numFrames / audioCompression->_uncompressedAudioFormat.mFramesPerPacket;

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
    // Cleanup manually, because ARC gets confused thinking we're holding onto the buffers which
    // we've shallow copied into the encoder. It can't see when the encoder is done with it.
    if (audioCompression->_uncompressedAudioDataContainer != nil) {
        [audioCompression->_uncompressedAudioDataContainer freeMemory];
    }
    audioCompression->_uncompressedAudioDataContainer = item;

    // Point compression engine to the PCM data.
    bool success = shallowCopyBuffers(ioData, sourceAudioBufferList);
    if (!success) {
        return kAudioConverterErr_UnspecifiedError;
    }

    printAudioBufferList(ioData, @"compression callback");
    return noErr;
}

- (void)compressionThreadEntryPoint:var {
    AudioClassDescription *description = [self
            getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
                            fromManufacturer:kAppleSoftwareAudioCodecManufacturer];

    OSStatus status = AudioConverterNewSpecific(&_uncompressedAudioFormat, &_compressedAudioFormat, 1, description, &_audioConverter);
    [self validateResult:status description:@"setting up audio converter"];

    bool isRunning = true;

    AudioBufferList audioBufferList = initializeAudioBufferList();
    AudioBufferList audioBufferListStartState = initializeAudioBufferList();

    allocateBuffersToAudioBufferListEx(&audioBufferList, 1, _compressedAudioFormat.mFramesPerPacket, 1, 1, true);
    shallowCopyBuffersEx(&audioBufferListStartState, &audioBufferList, ABL_BUFFER_NULL_OUT); // store original state, namely mBuffers[n].mDataByteSize.
    while (isRunning) {
        const int numFrames = 1;
        AudioStreamPacketDescription compressedPacketDescription[numFrames] = {0};
        UInt32 numFramesResult = numFrames;

        status = AudioConverterFillComplexBuffer(_audioConverter, pullUncompressedDataToAudioConverter, (__bridge void *) self, &numFramesResult, &audioBufferList, compressedPacketDescription);
        [self validateResult:status description:@"compressing audio data" logSuccess:false];

        for (int n = 0;n<audioBufferList.mNumberBuffers;n++) {
            NSLog(@"Compressed buffer size: %ul", audioBufferList.mBuffers[n].mDataByteSize);
        }

        // TODO: here we should write out to the network via a callback.
        // or for loopback, we can temporarily (for the purposes of testing) goto _audioToBeDecompressedQueue.

        // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
        resetBuffers(&audioBufferList, &audioBufferListStartState);
    }
    freeAudioBufferListEx(&audioBufferList, true);
}

- (AudioDataContainer *)getUncompressedItem {
    return [_audioToBeCompressedQueue get];
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [_audioToBeCompressedQueue add:audioData];
}

- (AudioDataContainer *)getPendingDecompressedData {
    //return [_audioToBeCompressedQueue getImmediate];
    return [_audioToBeOutputQueue getImmediate];
}


@end