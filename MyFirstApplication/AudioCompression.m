//
// Created by Michael Pryor on 21/02/2016.
//

#import "AudioCompression.h"
#import "BlockingQueue.h"

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
}

- (id)initWithAudioFormat:(AudioStreamBasicDescription)audioFormat {
    self = [super init];
    if (self) {
        _audioToBeCompressedQueue = [[BlockingQueue alloc] initWithMaxQueueSize:30];
        _audioToBeDecompressedQueue = [[BlockingQueue alloc] initWithMaxQueueSize:30];
        _audioToBeOutputQueue = [[BlockingQueue alloc] initWithMaxQueueSize:30];

        AudioStreamBasicDescription audioDescription;
        memset(&audioDescription, 0, sizeof(audioDescription));
        audioDescription.mFormatID = kAudioFormatMPEG4AAC;
        audioDescription.mChannelsPerFrame = 1;
        audioDescription.mSampleRate = 8000.0;
        audioDescription.mFramesPerPacket = 1024;

        // AudioConverterNew(&)
    }
    return self;
}

- (void)onNewAudioData:(AudioDataContainer *)audioData {
    [_audioToBeCompressedQueue add:audioData];
}

- (AudioDataContainer *)getPendingDecompressedData {
    return [_audioToBeOutputQueue getImmediate];
}


@end