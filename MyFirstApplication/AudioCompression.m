//
// Created by Michael Pryor on 21/02/2016.
//

#import "AudioCompression.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"
#import "Timer.h"

void printAudioBufferList(AudioBufferList *audioList, NSString* description) {
    for (int n = 0; n < audioList->mNumberBuffers; n++) {
        NSData* data = nil;//[NSData dataWithBytes:audioList->mBuffers[n].mData length:audioList->mBuffers[n].mDataByteSize];
        //NSLog(@"[ABL %@] buffer index %d (/%lu), channels %lu, size %lu, contents: %@", description, n, audioList->mNumberBuffers, audioList->mBuffers[n].mNumberChannels, audioList->mBuffers[n].mDataByteSize, data);
    }
}


AudioBufferList *allocateABL(UInt32 channelsPerFrame, UInt32 bytesPerFrame, bool interleaved, UInt32 capacityFrames) {
    AudioBufferList *bufferList = NULL;

    UInt32 numBuffers = interleaved ? 1 : channelsPerFrame;
    UInt32 channelsPerBuffer = interleaved ? channelsPerFrame : 1;

    bufferList = calloc(1, offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * numBuffers));

    bufferList->mNumberBuffers = numBuffers;

    for (UInt32 bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; ++bufferIndex) {
        bufferList->mBuffers[bufferIndex].mData = calloc(capacityFrames, bytesPerFrame);
        bufferList->mBuffers[bufferIndex].mDataByteSize = capacityFrames * bytesPerFrame;
        bufferList->mBuffers[bufferIndex].mNumberChannels = channelsPerBuffer;
    }

    return bufferList;
}

AudioBufferList *cloneAudioList(AudioBufferList *copyFrom) {
    AudioBufferList *audioList;
    size_t size = sizeof(AudioBufferList) + (copyFrom->mNumberBuffers - 1) * sizeof(AudioBuffer);
    audioList = malloc(size);
    audioList->mNumberBuffers = copyFrom->mNumberBuffers;
    for (int n = 0; n < copyFrom->mNumberBuffers; n++) {
        audioList[n].mBuffers[n].mDataByteSize = copyFrom->mBuffers[n].mDataByteSize;
        audioList[n].mBuffers[n].mNumberChannels = copyFrom->mBuffers[n].mNumberChannels;
        audioList[n].mBuffers[n].mData = malloc(audioList[n].mBuffers[n].mDataByteSize);
        memcpy(audioList[n].mBuffers[n].mData, copyFrom->mBuffers[n].mData, audioList[n].mBuffers[n].mDataByteSize);
    }
    return audioList;
}

@implementation AudioDataContainer {

}

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList {
    self = [super init];
    if (self) {
        _numFrames = numFrames;
        _audioList = cloneAudioList(audioList);
        printAudioBufferList(_audioList, @"container init");
    }
    return self;
}

- (void)dealloc {
    //  free(_audioList);
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

    char * _pcmBuffer;
}

- (id)initWithAudioFormat:(AudioStreamBasicDescription)uncompressedAudioFormat {
    self = [super init];
    if (self) {
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

- (void) copyPCMSamplesIntoBuffer:(AudioBufferList*)ioData fromAudioList:(AudioBufferList*)list {
    ioData->mNumberBuffers = list->mNumberBuffers;
    ioData->mBuffers[0].mData = list->mBuffers[0].mData;
    ioData->mBuffers[0].mDataByteSize = list->mBuffers[0].mDataByteSize;
    _pcmBuffer = NULL;
}

// Converting PCM to AAC.
OSStatus pullUncompressedDataToAudioConverter(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioCompression *_audioCompression = (__bridge AudioCompression *) inUserData;

    AudioDataContainer *item = [_audioCompression getUncompressedItem];

    // 1 frame per packet.
    if (item.numFrames * 4 != item.audioList->mBuffers[0].mDataByteSize) {
        NSLog(@"Mistmatch, num frames = %lu, mult4 = %lu, byte size = %lu", item.numFrames, item.numFrames * 4, item.audioList->mBuffers[0].mDataByteSize);
    }
    *ioNumberDataPackets = item.numFrames;

    AudioBufferList *sourceAudioBufferList = [item audioList];
    if (ioData->mNumberBuffers > sourceAudioBufferList->mNumberBuffers) {
        NSLog(@"Problem, more source buffers than destination");
        return -1;
    }

    if (outDataPacketDescription != NULL) {
        NSLog(@"outDataPacketDescription is not NULL, unexpected");
    }

    [_audioCompression copyPCMSamplesIntoBuffer:ioData fromAudioList:sourceAudioBufferList];
    printAudioBufferList(ioData, @"compression callback");

    //NSLog(@"Callback called");

    return noErr;
}

- (void)compressionThreadEntryPoint:var {
    AudioClassDescription *description = [self
            getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
                            fromManufacturer:kAppleSoftwareAudioCodecManufacturer];

    OSStatus status = AudioConverterNewSpecific(&_uncompressedAudioFormat, &_compressedAudioFormat, 1, description, &_audioConverter);
    [self validateResult:status description:@"setting up audio converter"];

   /* UInt32 ulBitRate = 44100;
    UInt32 ulSize = sizeof(ulBitRate);
    status = AudioConverterSetProperty(_audioConverter, kAudioConverterEncodeBitRate, ulSize, &ulBitRate);
    [self validateResult:status description:@"setting audio converter bit rate"];*/


    bool isRunning = true;
    Timer *timer = [[Timer alloc] initWithFrequencySeconds:1 firingInitially:false];
    int count = 0;
    while (isRunning) {
        AudioBufferList *audioBufferList = allocateABL(_compressedAudioFormat.mChannelsPerFrame, 1024, true, 1);
        const int numFrames = 1;
        AudioStreamPacketDescription compressedPacketDescription[numFrames] = {0};
        UInt32 numFramesResult = numFrames;

        status = AudioConverterFillComplexBuffer(_audioConverter, pullUncompressedDataToAudioConverter, (__bridge void *) self, &numFramesResult, audioBufferList, compressedPacketDescription);
        [self validateResult:status description:@"compressing audio data" logSuccess:false];
        count++;

         /*for (int n = 0;n<audioBufferList->mNumberBuffers;n++) {
             NSLog(@"Compressed buffer size: %ul", audioBufferList->mBuffers[n].mDataByteSize);
         }*/

        if ([timer getState]) {
           // NSLog(@"We have had %d compression results in the last second", count);
            count = 0;
        }
    }
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