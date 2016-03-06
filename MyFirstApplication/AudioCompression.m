//
// Created by Michael Pryor on 21/02/2016.
//

#import "AudioCompression.h"
#import "SoundEncodingShared.h"
#import "AudioUnitHelpers.h"
#import "TimedCounterLogging.h"


@implementation AudioCompression {
    // Audio input (microphone) --> audioToBeCompressedQueue --> [compression] --> [network] --> audioToBeDecompressedQueue --> [decompression] --> audioToBeOutputQueue
    BlockingQueue *_audioToBeCompressedQueue;

    BlockingQueue *_audioToBeDecompressedQueue;

    BlockingQueue *_audioToBeOutputQueue;

    NSThread *_compressionThread;
    bool _isRunningCompression;

    NSThread *_decompressionThread;
    bool _isRunningDecompression;


    AudioStreamBasicDescription _compressedAudioFormat;
    AudioStreamBasicDescription _uncompressedAudioFormat;
    uint numFramesToDecompressPerOperation;


    // To decompress, we need a description for each AAC packet.
    AudioStreamPacketDescription _compressedDescription;

    // We keep a reference to this to prevent it being cleaned up while the data is being compressed.
    // Documentation states we must not cleanup between callbacks, but during next cleanup can cleanup,
    // which means that it is sufficient to maintain one reference here.
    AudioDataContainer *_uncompressedAudioDataContainer;
    AudioDataContainer *_compressedAudioDataContainer;

    AudioClassDescription *_compressionClass;

    // Push compressed packets out to this session.
    id <NewPacketDelegate> _outputSession;

    // Network keeps some bytes for its protocol.
    UInt32 _leftPadding;

    // Track byte sizes, just for our information.
    TimedCounterLogging *_compressedInboundSizeCounter;
    TimedCounterLogging *_compressedOutboundSizeCounter;
    TimedCounterLogging *_decompressedInboundSizeCounter;
    TimedCounterLogging *_decompressedOutboundSizeCounter;
}

- (id)initWithUncompressedAudioFormat:(AudioStreamBasicDescription)uncompressedAudioFormat uncompressedAudioFormatEx:(AudioFormatProcessResult)uncompressedAudioFormatEx outputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding outboundQueue:(BlockingQueue *)outboundQueue {
    self = [super init];
    if (self) {
        _isRunningDecompression = false;
        _isRunningCompression = false;

        _compressedInboundSizeCounter = [[TimedCounterLogging alloc] initWithDescription:@"compressed inbound"];
        _compressedOutboundSizeCounter = [[TimedCounterLogging alloc] initWithDescription:@"compressed outbound"];
        _decompressedInboundSizeCounter = [[TimedCounterLogging alloc] initWithDescription:@"decompressed inbound"];
        _decompressedOutboundSizeCounter = [[TimedCounterLogging alloc] initWithDescription:@"decompressed outbound"];

        _outputSession = outputSession;
        _leftPadding = leftPadding;

        _uncompressedAudioDataContainer = nil;
        _compressedAudioDataContainer = nil;

        // Get about half a second 1 second delay at worst.
        // TODO: Consider impact of these values.
        _audioToBeCompressedQueue = [[BlockingQueue alloc] initWithName:@"compression AAC inbound" maxQueueSize:100];
        _audioToBeDecompressedQueue = [[BlockingQueue alloc] initWithName:@"decompression AAC inbound" maxQueueSize:100];
        if (outboundQueue == nil) {
            _audioToBeOutputQueue = [[BlockingQueue alloc] initWithName:@"decompression AAC outbound" maxQueueSize:100];
        } else {
            _audioToBeOutputQueue = outboundQueue;
        }

        _uncompressedAudioFormat = uncompressedAudioFormat;
        numFramesToDecompressPerOperation = uncompressedAudioFormatEx.framesPerBuffer;

        // Compression does not care about the PCM sample rate.
        // This is important because sample rate may change when plugging in earphones, or unplugging them.
        //_uncompressedAudioFormat.mSampleRate = 0;

        AudioStreamBasicDescription compressedAudioDescription = {0};
        compressedAudioDescription.mFormatID = kAudioFormatMPEG4AAC;
        compressedAudioDescription.mChannelsPerFrame = 1;
        compressedAudioDescription.mSampleRate = uncompressedAudioFormat.mSampleRate;
        compressedAudioDescription.mFramesPerPacket = 1024;
        compressedAudioDescription.mFormatFlags = 0;
        _compressedAudioFormat = compressedAudioDescription;

        _compressionClass = getAudioClassDescriptionWithType(kAudioFormatMPEG4AAC, kAppleSoftwareAudioCodecManufacturer);
    }
    return self;
}

- (void)initialize {
    @synchronized (self) {
        NSLog(@"Initializing AAC audio compression and decompression");
        _isRunningDecompression = true;
        _isRunningCompression = true;
        _decompressionThread = [[NSThread alloc] initWithTarget:self
                                                       selector:@selector(decompressionThreadEntryPoint:)
                                                         object:nil];
        [_decompressionThread setName:@"Audio Decompression"];
        [_decompressionThread start];


        _compressionThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(compressionThreadEntryPoint:)
                                                       object:nil];
        [_compressionThread setName:@"Audio Compression"];
        [_compressionThread start];
    }
}

- (void)terminate {
    @synchronized (self) {
        NSLog(@"Terminating AAC audio compression and decompression");
        _isRunningDecompression = false;
        _isRunningCompression = false;
        [_audioToBeCompressedQueue shutdown];
        [_audioToBeDecompressedQueue shutdown];
    }
}

- (void)dealloc {
    [self terminate];
}

- (void)reset {
    [_audioToBeCompressedQueue clear];
    [_audioToBeDecompressedQueue clear];
    [_audioToBeOutputQueue clear];
}

// Converting PCM to AAC.
OSStatus pullUncompressedDataToAudioConverter(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioCompression *audioCompression = (__bridge AudioCompression *) inUserData;

    AudioDataContainer *item;
    do {
        item = [audioCompression getUncompressedItem];
        if (item == nil) {
            return kAudioConverterErr_UnspecifiedError;
        }
    } while (![item isValid]);

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

    return noErr;
}

- (void)compressionThreadEntryPoint:var {
    AudioConverterRef audioConverter;

    OSStatus status = AudioConverterNewSpecific(&_uncompressedAudioFormat, &_compressedAudioFormat, 1, _compressionClass, &audioConverter);
    [self validateResult:status description:@"setting up audio converter"];

    AudioBufferList audioBufferList = initializeAudioBufferList();
    AudioBufferList audioBufferListStartState = initializeAudioBufferList();

    allocateBuffersToAudioBufferListEx(&audioBufferList, 1, _compressedAudioFormat.mFramesPerPacket, 1, 1, true);
    shallowCopyBuffersEx(&audioBufferListStartState, &audioBufferList, ABL_BUFFER_NULL_OUT); // store original state, namely mBuffers[n].mDataByteSize.

    while (_isRunningCompression) {
        @autoreleasepool {
            const UInt32 maxNumFrames = 1;
            AudioStreamPacketDescription compressedPacketDescription[maxNumFrames] = {0};
            UInt32 numFramesResult = maxNumFrames;

            status = AudioConverterFillComplexBuffer(audioConverter, pullUncompressedDataToAudioConverter, (__bridge void *) self, &numFramesResult, &audioBufferList, compressedPacketDescription);
            [self validateResult:status description:@"compressing audio data" logSuccess:false];

            if (numFramesResult > audioBufferList.mNumberBuffers || numFramesResult > maxNumFrames) {
                NSLog(@"After compression, number of frames (%lu) is greater than number of buffers (%lu) or maximum number of frames (%lu)", numFramesResult, audioBufferList.mNumberBuffers, maxNumFrames);
                continue;
            }

            bool problemDetected = false;
            for (int n = 0; n < numFramesResult; n++) {
                AudioStreamPacketDescription compressedPacketDescriptionItem = compressedPacketDescription[n];
                AudioBuffer *buffer = &audioBufferList.mBuffers[n];

                if (compressedPacketDescriptionItem.mVariableFramesInPacket > 0) {
                    NSLog(@"Variable frames detected in compressed data, this is not supported");
                    problemDetected = true;
                    break;
                }

                if (compressedPacketDescriptionItem.mDataByteSize != buffer->mDataByteSize) {
                    NSLog(@"Mismatch in packet description and packet data, %lu vs %lu", compressedPacketDescriptionItem.mDataByteSize, buffer->mDataByteSize);
                    problemDetected = true;
                    break;
                }
            }

            if (problemDetected) {
                continue;
            }

            AudioDataContainer *resultingContainer = [[AudioDataContainer alloc] initWithNumFrames:numFramesResult audioList:&audioBufferList];
            [resultingContainer incrementCounter:_compressedOutboundSizeCounter];

            if (_outputSession != nil) {
                // Write out to network callback, in production code we should always do this.
                ByteBuffer *byteBuffer = [resultingContainer buildByteBufferWithLeftPadding:_leftPadding];
                [_outputSession onNewPacket:byteBuffer fromProtocol:UDP];
            } else {
                // Loopback for testing, we can temporarily for the purposes of testing go straight
                // to the network inbound queue, so that the data is immediately decompressed
                // and sent to the speaker.
                [resultingContainer incrementCounter:_decompressedInboundSizeCounter];
                [_audioToBeDecompressedQueue add:resultingContainer];
            }

            // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
            resetBuffers(&audioBufferList, &audioBufferListStartState);
        }
    }
    freeAudioBufferListEx(&audioBufferList, true);

    status = AudioConverterDispose(audioConverter);
    [self validateResult:status description:@"disposing of compression audio converter"];
}


// Converting AAC to PCM.
OSStatus pullCompressedDataToAudioConverter(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioCompression *audioCompression = (__bridge AudioCompression *) inUserData;

    AudioDataContainer *item;
    do {
        item = [audioCompression getCompressedItem];
        if (item == nil) {
            return kAudioConverterErr_UnspecifiedError;
        }
    } while (![item isValid]);

    *ioNumberDataPackets = 1;

    AudioBufferList *sourceAudioBufferList = [item audioList];

    // Validation.
    if (ioData->mNumberBuffers > 1) {
        NSLog(@"Problem, expected only one buffer");
        return kAudioConverterErr_UnspecifiedError;
    }

    if (outDataPacketDescription == NULL) {
        NSLog(@"outDataPacketDescription is NULL, unexpected when decompressing");
        return kAudioConverterErr_UnspecifiedError;
    }


    *outDataPacketDescription = &audioCompression->_compressedDescription;
    AudioStreamPacketDescription *description = *outDataPacketDescription;
    description->mStartOffset = 0;
    description->mVariableFramesInPacket = 0;
    description->mDataByteSize = sourceAudioBufferList->mBuffers[0].mDataByteSize;


    // Maintain reference to prevent cleanup while buffers are being used.
    // Cleanup manually, because ARC gets confused thinking we're holding onto the buffers which
    // we've shallow copied into the encoder. It can't see when the decoder is done with it.
    if (audioCompression->_compressedAudioDataContainer != nil) {
        [audioCompression->_compressedAudioDataContainer freeMemory];
    }
    audioCompression->_compressedAudioDataContainer = item;

    // Point compression engine to the PCM data.
    bool success = shallowCopyBuffers(ioData, sourceAudioBufferList);
    if (!success) {
        return kAudioConverterErr_UnspecifiedError;
    }

    return noErr;
}

- (void)decompressionThreadEntryPoint:var {
    AudioConverterRef audioConverterDecompression;

    OSStatus status = AudioConverterNewSpecific(&_compressedAudioFormat, &_uncompressedAudioFormat, 1, _compressionClass, &audioConverterDecompression);
    [self validateResult:status description:@"setting up audio converter"];

    AudioBufferList audioBufferList = initializeAudioBufferList();
    AudioBufferList audioBufferListStartState = initializeAudioBufferList();

    allocateBuffersToAudioBufferListEx(&audioBufferList, 1, numFramesToDecompressPerOperation * _uncompressedAudioFormat.mBytesPerFrame, 1, 1, true);
    shallowCopyBuffersEx(&audioBufferListStartState, &audioBufferList, ABL_BUFFER_NULL_OUT); // store original state, namely mBuffers[n].mDataByteSize.

    while (_isRunningDecompression) {
        @autoreleasepool {
            UInt32 numFramesResult = numFramesToDecompressPerOperation;

            status = AudioConverterFillComplexBuffer(audioConverterDecompression, pullCompressedDataToAudioConverter, (__bridge void *) self, &numFramesResult, &audioBufferList, NULL);
            if ([self validateResult:status description:@"decompressing audio data" logSuccess:false]) {
                [_audioToBeOutputQueue add:[[AudioDataContainer alloc] initWithNumFrames:numFramesResult audioList:&audioBufferList]];
            }

            // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
            resetBuffers(&audioBufferList, &audioBufferListStartState);
        }
    }
    freeAudioBufferListEx(&audioBufferList, true);

    status = AudioConverterDispose(audioConverterDecompression);
    [self validateResult:status description:@"disposing of decompression audio converter"];
}

- (AudioDataContainer *)getUncompressedItem {
    return [_audioToBeCompressedQueue get];
}

- (AudioDataContainer *)getCompressedItem {
    return [_audioToBeDecompressedQueue get];
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description logSuccess:(bool)logSuccess {
    return HandleResultOSStatus(result, description, logSuccess);
}

- (bool)validateResult:(OSStatus)result description:(NSString *)description {
    return [self validateResult:result description:description logSuccess:true];
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [audioData incrementCounter:_compressedInboundSizeCounter];
    [_audioToBeCompressedQueue add:audioData];
}

- (AudioDataContainer *)getPendingDecompressedData {
    AudioDataContainer *audioData = [_audioToBeOutputQueue getImmediate];
    [audioData incrementCounter:_decompressedOutboundSizeCounter];
    return audioData;
}


- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    AudioDataContainer *audioData = [[AudioDataContainer alloc] initWithNumFrames:1 fromByteBuffer:packet audioFormat:&_compressedAudioFormat];
    [_audioToBeDecompressedQueue add:audioData];
    [audioData incrementCounter:_decompressedInboundSizeCounter];
}


@end