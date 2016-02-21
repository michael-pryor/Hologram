//
// Created by Michael Pryor on 21/02/2016.
//

#import "AudioCompression.h"
#import "BlockingQueue.h"
#import "SoundEncodingShared.h"

AudioBufferList * allocateABL(UInt32 channelsPerFrame, UInt32 bytesPerFrame, bool interleaved, UInt32 capacityFrames) {
    AudioBufferList *bufferList = NULL;

    UInt32 numBuffers = interleaved ? 1 : channelsPerFrame;
    UInt32 channelsPerBuffer = interleaved ? channelsPerFrame : 1;

    bufferList = calloc(1, offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * numBuffers));

    bufferList->mNumberBuffers = numBuffers;

    for(UInt32 bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; ++bufferIndex) {
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
    memcpy(audioList, copyFrom, size);
    return audioList;
}

@implementation AudioDataContainer {

}

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList {
    self = [super init];
    if (self) {
        _numFrames = numFrames;
        _audioList = cloneAudioList(audioList);
    }
    return self;
}

- (void)dealloc {
    free(_audioList);
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
        compressedAudioDescription.mSampleRate = 8000.0;
        compressedAudioDescription.mFramesPerPacket = 1024;
        _compressedAudioFormat = compressedAudioDescription;

        OSStatus status = AudioConverterNew(&_uncompressedAudioFormat, &compressedAudioDescription, &_audioConverter);
        [self validateResult:status description:@"setting up audio converter"];
    }
    return self;
}

- (void)initialize {
    _compressionThread = [[NSThread alloc] initWithTarget:self
                                            selector:@selector(compressionThreadEntryPoint:)
                                              object:nil];
    [_compressionThread setName:@"Audio Compression"];
    [_compressionThread start];
}

// Converting PCM to AAC.
OSStatus pullUncompressedDataToAudioConverter ( AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData ) {
    AudioCompression *_audioCompression = (__bridge AudioCompression*)inUserData;

    AudioDataContainer * item = [_audioCompression getUncompressedItem];
    *ioNumberDataPackets = [item numFrames];

    AudioBufferList *sourceAudioBufferList = [item audioList];
    if (ioData->mNumberBuffers > sourceAudioBufferList->mNumberBuffers) {
        NSLog(@"Problem, more source buffers than destination");
        return -1;
    }

    if (outDataPacketDescription != NULL) {
        NSLog(@"outDataPacketDescription is not NULL, unexpected");
    }

    ioData->mNumberBuffers = sourceAudioBufferList->mNumberBuffers;
    memcpy(ioData->mBuffers, sourceAudioBufferList->mBuffers, sizeof(AudioBuffer) * ioData->mNumberBuffers);

    return noErr;
}

- (void)compressionThreadEntryPoint:var {
    bool isRunning = true;
    while (isRunning) {
        AudioBufferList *audioBufferList = allocateABL(_compressedAudioFormat.mChannelsPerFrame, _compressedAudioFormat.mFramesPerPacket, true, 1);
        AudioStreamPacketDescription compressedPacketDescription = {0};

        UInt32 numFrames = 1;
        OSStatus status = AudioConverterFillComplexBuffer(_audioConverter, &pullUncompressedDataToAudioConverter, (__bridge void*)self, &numFrames, audioBufferList, &compressedPacketDescription);
        [self validateResult:status description:@"compressing audio data"];
    }
}

- (AudioDataContainer*)getUncompressedItem {
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