//
// Created by Michael Pryor on 05/03/2016.
//

#import "AudioUnitHelpers.h"
#import "ByteBuffer.h"
#import "AudioShared.h"
#import "BlockingQueue.h"
#import "BlockingQueueTemporal.h"

@implementation AudioDataContainer
- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList {
    self = [super init];
    if (self) {
        _numFrames = numFrames;
        if (audioList != nil) {
            _audioList = cloneAudioBufferList(audioList);
        }
    }
    return self;
}

- (id)initWithNumFrames:(UInt32)numFrames fromByteBuffer:(ByteBuffer *)byteBuffer audioFormat:(AudioStreamBasicDescription *)description {
    self = [super init];
    if (self) {
        _numFrames = numFrames;
        UInt32 bytesToCopy = [byteBuffer getUnreadDataFromCursor];

        // Takes into account cursor position.
        [byteBuffer getVariableLengthData:^id(uint8_t *data, uint length) {
            _audioList = initializeAudioBufferListHeapSingle(length, description->mChannelsPerFrame);
            AudioBuffer *buffer = &_audioList->mBuffers[0];
            buffer->mDataByteSize = length;
            memcpy(buffer->mData, data, length);

            return nil; // we populate _audioList direct.
        }                      withLength:bytesToCopy];
    }
    return self;
}

- (ByteBuffer *)buildByteBufferWithLeftPadding:(uint)leftPadding {
    if (_audioList->mNumberBuffers != 1) {
        NSLog(@"Could not build byte buffer, need exactly 1 buffer");
        return nil;
    }
    AudioBuffer *buffer = &_audioList->mBuffers[0];

    ByteBuffer *byteBuffer = [[ByteBuffer alloc] initWithSize:_audioList->mBuffers[0].mDataByteSize + leftPadding];
    [byteBuffer addVariableLengthData:buffer->mData withLength:buffer->mDataByteSize includingPrefix:false atPosition:leftPadding];

    return byteBuffer;
}

- (void)incrementCounter:(TimedCounter *)counter {
    if ([self audioList] == nil || [self audioList]->mNumberBuffers != 1) {
        return;
    }

    [counter incrementBy:[self audioList]->mBuffers[0].mDataByteSize];
}

- (void)freeMemory {
    if (_audioList != NULL) {
        freeAudioBufferList(_audioList);
        _audioList = NULL;
    }
}

- (void)dealloc {
    [self freeMemory];
}

- (bool)isValid {
    return _audioList != nil && _numFrames > 0;
}
@end

BlockingQueue* buildAudioQueue(NSString* name) {
    return [[BlockingQueueTemporal alloc] initWithName:name maxQueueSize:100 trackerResetFrequencySeconds:5 minimumThreshold:3];
}