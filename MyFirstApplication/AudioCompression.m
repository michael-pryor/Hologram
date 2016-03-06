//
// Created by Michael Pryor on 21/02/2016.
//

#import "AudioCompression.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"
#import "AudioUnitHelpers.h"
#import "Signal.h"
#import "InputSessionBase.h"
#import "TimedCounter.h"


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

    // To decompress, we need a description for each AAC packet.
    AudioStreamPacketDescription _compressedDescription;

    // We keep a reference to this to prevent it being cleaned up while the data is being compressed.
    // Documentation states we must not cleanup between callbacks, but during next cleanup can cleanup,
    // which means that it is sufficient to maintain one reference here.
    AudioDataContainer *_uncompressedAudioDataContainer;
    AudioDataContainer *_compressedAudioDataContainer;

    AudioClassDescription *_compressionClass;

    char *_magicCookie;
    UInt32 _magicCookieSize;
    Signal *_magicCookieLoaded;

    // Push compressed packets out to this session.
    id <NewPacketDelegate> _outputSession;

    // Network keeps some bytes for its protocol.
    UInt32 _leftPadding;

    // Track byte sizes, just for our information.
    TimedCounter *_compressedInboundSizeCounter;
    TimedCounter *_compressedOutboundSizeCounter;
    TimedCounter *_decompressedInboundSizeCounter;
    TimedCounter *_decompressedOutboundSizeCounter;
}

- (id)initWithAudioFormat:(AudioStreamBasicDescription)uncompressedAudioFormat outputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding outboundQueue:(BlockingQueue*)outboundQueue {
    self = [super init];
    if (self) {
        _isRunningDecompression = false;
        _isRunningCompression = false;

        const uint freqSeconds = 60;
        _compressedInboundSizeCounter = [[TimedCounter alloc] initWithTimer:[[Timer alloc] initWithFrequencySeconds:freqSeconds firingInitially:false]];
        _compressedOutboundSizeCounter = [[TimedCounter alloc] initWithTimer:[[Timer alloc] initWithFrequencySeconds:freqSeconds firingInitially:false]];
        _decompressedInboundSizeCounter = [[TimedCounter alloc] initWithTimer:[[Timer alloc] initWithFrequencySeconds:freqSeconds firingInitially:false]];
        _decompressedOutboundSizeCounter = [[TimedCounter alloc] initWithTimer:[[Timer alloc] initWithFrequencySeconds:freqSeconds firingInitially:false]];

        _outputSession = outputSession;
        _leftPadding = leftPadding;

        _uncompressedAudioDataContainer = nil;
        _compressedAudioDataContainer = nil;
        _magicCookie = NULL;
        _magicCookieSize = 0;

        _magicCookieLoaded = [[Signal alloc] initWithFlag:false];

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

        // Compression does not care about the PCM sample rate.
        // This is important because sample rate may change when plugging in earphones, or unplugging them.
        //_uncompressedAudioFormat.mSampleRate = 0;

        AudioStreamBasicDescription compressedAudioDescription = {0};
        compressedAudioDescription.mFormatID = kAudioFormatMPEG4AAC;
        compressedAudioDescription.mChannelsPerFrame = 1;
        compressedAudioDescription.mSampleRate = 8000.0;
        compressedAudioDescription.mFramesPerPacket = 1024;
        compressedAudioDescription.mFormatFlags = 0;
        _compressedAudioFormat = compressedAudioDescription;

        _compressionClass = getAudioClassDescriptionWithType(kAudioFormatMPEG4AAC, kAppleSoftwareAudioCodecManufacturer);
    }
    return self;
}

- (void)initialize {
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

- (void)terminate {
    _isRunningDecompression = false;
    _isRunningCompression = false;
}

- (void)dealloc {
    [self terminate];
    free(_magicCookie);
}

- (void)reset {
    [_audioToBeCompressedQueue clear];
    [_audioToBeDecompressedQueue clear];
    [_audioToBeOutputQueue clear];
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
    AudioConverterRef audioConverter;

    OSStatus status = AudioConverterNewSpecific(&_uncompressedAudioFormat, &_compressedAudioFormat, 1, _compressionClass, &audioConverter);
    [self validateResult:status description:@"setting up audio converter"];

    _magicCookie = getMagicCookieFromAudioConverter(audioConverter, &_magicCookieSize);
    [_magicCookieLoaded signalAll];

    AudioBufferList audioBufferList = initializeAudioBufferList();
    AudioBufferList audioBufferListStartState = initializeAudioBufferList();

    allocateBuffersToAudioBufferListEx(&audioBufferList, 1, _compressedAudioFormat.mFramesPerPacket, 1, 1, true);
    shallowCopyBuffersEx(&audioBufferListStartState, &audioBufferList, ABL_BUFFER_NULL_OUT); // store original state, namely mBuffers[n].mDataByteSize.

    _isRunningCompression = true;
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

            /*for (int n = 0; n < audioBufferList.mNumberBuffers; n++) {
                NSLog(@"Compressed buffer size: %lu, pd size: %lu, pd variable frames %lu", audioBufferList.mBuffers[n].mDataByteSize, compressedPacketDescription[0].mDataByteSize, compressedPacketDescription[0].mStartOffset, compressedPacketDescription[0].mVariableFramesInPacket);
            }*/

            AudioDataContainer *resultingContainer = [[AudioDataContainer alloc] initWithNumFrames:numFramesResult audioList:&audioBufferList];
            [AudioDataContainer handleTimedCounter:_compressedOutboundSizeCounter description:@"compressed outbound" incrementContainer:resultingContainer];

            if (_outputSession != nil) {
                // Write out to network callback, in production code we should always do this.
                ByteBuffer *byteBuffer = [resultingContainer buildByteBufferWithLeftPadding:_leftPadding];
                [_outputSession onNewPacket:byteBuffer fromProtocol:UDP];
            } else {
                // Loopback for testing, we can temporarily for the purposes of testing go straight
                // to the network inbound queue, so that the data is immediately decompressed
                // and sent to the speaker.
                [AudioDataContainer handleTimedCounter:_decompressedInboundSizeCounter description:@"decompressed inbound" incrementContainer:resultingContainer];
                [_audioToBeDecompressedQueue add:resultingContainer];
            }

            // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
            resetBuffers(&audioBufferList, &audioBufferListStartState);
        }
    }
    freeAudioBufferListEx(&audioBufferList, true);
}


// Converting AAC to PCM.
OSStatus pullCompressedDataToAudioConverter(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioCompression *audioCompression = (__bridge AudioCompression *) inUserData;

    AudioDataContainer *item = [audioCompression getCompressedItem];

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

    printAudioBufferList(ioData, @"decompression callback");
    return noErr;
}

- (void)decompressionThreadEntryPoint:var {
    AudioConverterRef audioConverterDecompression;

    OSStatus status = AudioConverterNewSpecific(&_compressedAudioFormat, &_uncompressedAudioFormat, 1, _compressionClass, &audioConverterDecompression);
    [self validateResult:status description:@"setting up audio converter"];

    [_magicCookieLoaded wait];
    status = loadMagicCookieIntoAudioConverter(audioConverterDecompression, _magicCookie, _magicCookieSize);
    [self validateResult:status description:@"loading magic cookie into decompression audio converter"];

    AudioBufferList audioBufferList = initializeAudioBufferList();
    AudioBufferList audioBufferListStartState = initializeAudioBufferList();

    const int numFrames = 10;
    allocateBuffersToAudioBufferListEx(&audioBufferList, 1, numFrames * _uncompressedAudioFormat.mBytesPerFrame, 1, 1, true);
    shallowCopyBuffersEx(&audioBufferListStartState, &audioBufferList, ABL_BUFFER_NULL_OUT); // store original state, namely mBuffers[n].mDataByteSize.

    _isRunningDecompression = true;
    while (_isRunningDecompression) {
        @autoreleasepool {
            UInt32 numFramesResult = numFrames;

            status = AudioConverterFillComplexBuffer(audioConverterDecompression, pullCompressedDataToAudioConverter, (__bridge void *) self, &numFramesResult, &audioBufferList, NULL);
            [self validateResult:status description:@"decompressing audio data" logSuccess:false];

            /*for (int n = 0; n < audioBufferList.mNumberBuffers; n++) {
                NSLog(@"Decompressed buffer size: %lu", audioBufferList.mBuffers[n].mDataByteSize);
            }*/

            [_audioToBeOutputQueue add:[[AudioDataContainer alloc] initWithNumFrames:numFramesResult audioList:&audioBufferList]];

            // Reset mBuffers[n].mDataByteSize so that buffer can be reused.
            resetBuffers(&audioBufferList, &audioBufferListStartState);
        }
    }
    freeAudioBufferListEx(&audioBufferList, true);
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
    [AudioDataContainer handleTimedCounter:_compressedInboundSizeCounter description:@"compressed inbound" incrementContainer:audioData];
    [_audioToBeCompressedQueue add:audioData];
}

- (AudioDataContainer *)getPendingDecompressedData {
    AudioDataContainer *container =  [_audioToBeOutputQueue getImmediate];
    [AudioDataContainer handleTimedCounter:_decompressedOutboundSizeCounter description:@"decompressed outbound" incrementContainer:container];
    return container;
}


- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    AudioDataContainer *container = [[AudioDataContainer alloc] initFromByteBuffer:packet audioFormat:&_compressedAudioFormat];
    [_audioToBeDecompressedQueue add:container];
    [AudioDataContainer handleTimedCounter:_decompressedInboundSizeCounter description:@"decompressed inbound" incrementContainer:container];
}


@end