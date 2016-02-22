//
// Created by Michael Pryor on 22/02/2016.
//

#import "AudioUnitHelpers.h"

void printAudioBufferList(AudioBufferList *audioList, NSString *description) {
    //for (int n = 0; n < audioList->mNumberBuffers; n++) {
    //NSData *data = [NSData dataWithBytes:audioList->mBuffers[n].mData length:audioList->mBuffers[n].mDataByteSize];
    // NSLog(@"[ABL %@] buffer index %d (/%lu), channels %lu, size %lu, contents: %@", description, n, audioList->mNumberBuffers, audioList->mBuffers[n].mNumberChannels, audioList->mBuffers[n].mDataByteSize, data);
    //}
}

// Neat trick to get around the seemingly non resizable audioList->mBuffers[1].
// Because mBuffers is at the end of the struct, we can add more memory to the structure and resize freely.
// This is by design; by Apple.
UInt32 getNumBytesForAudioBufferList(UInt32 numBuffers) {
    return offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * numBuffers);
}

void getAudioBufferListParameters(UInt32 numPackets, UInt32 channelsPerFrame, bool channelsInterleaved, UInt32 *numBuffersOut, UInt32 *channelsPerBufferOut) {
    // If interleaved then every other byte of a buffer represents one channel.
    // If not interleaved, then each channel has its own buffer.
    if (channelsInterleaved) {
        *numBuffersOut = numPackets;
        *channelsPerBufferOut = channelsPerFrame;
    } else {
        *numBuffersOut = channelsPerFrame * numPackets;
        *channelsPerBufferOut = 1;
    }
}

// Other methods check mNumberBuffers; a buffer list initialized on the stack
// has 1 buffer, but we need to initialize mNumberBuffers manually.
AudioBufferList initializeAudioBufferList() {
    AudioBufferList audioBufferList;
    audioBufferList.mNumberBuffers = 1;
    return audioBufferList;
};

AudioBufferList *allocateBuffersToAudioBufferList(AudioBufferList *destinationAudioBufferList, UInt32 bytesPerFrame, UInt32 framesPerPacket, UInt32 numBuffers, UInt32 channelsPerBuffer) {
    if (destinationAudioBufferList->mNumberBuffers < numBuffers) {
        NSLog(@"Cannot copy buffers over, destination audio buffer list is too small (allocateBuffersToAudioBufferList)");
        return false;
    }

    destinationAudioBufferList->mNumberBuffers = numBuffers;

    for (UInt32 bufferIndex = 0; bufferIndex < destinationAudioBufferList->mNumberBuffers; ++bufferIndex) {
        AudioBuffer *destinationAudioBuffer = &destinationAudioBufferList->mBuffers[bufferIndex];
        destinationAudioBuffer->mData = calloc(framesPerPacket, bytesPerFrame);
        destinationAudioBuffer->mDataByteSize = framesPerPacket * bytesPerFrame;
        destinationAudioBuffer->mNumberChannels = channelsPerBuffer;
    }

    return destinationAudioBufferList;
}

AudioBufferList *allocateBuffersToAudioBufferListEx(AudioBufferList *destinationAudioBufferList, UInt32 bytesPerFrame, UInt32 framesPerPacket, UInt32 numPackets, UInt32 channelsPerFrame, bool channelsInterleaved) {
    UInt32 numBuffers;
    UInt32 channelsPerBuffer;
    getAudioBufferListParameters(numPackets, channelsPerFrame, channelsInterleaved, &numBuffers, &channelsPerBuffer);

    return allocateBuffersToAudioBufferList(destinationAudioBufferList, bytesPerFrame, framesPerPacket, numBuffers, channelsPerBuffer);
}

AudioBufferList *allocateAudioBufferList(UInt32 bytesPerFrame, UInt32 framesPerPacket, UInt32 numPackets, UInt32 channelsPerFrame, bool channelsInterleaved) {
    AudioBufferList *bufferList = NULL;

    UInt32 numBuffers;
    UInt32 channelsPerBuffer;
    getAudioBufferListParameters(numPackets, channelsPerFrame, channelsInterleaved, &numBuffers, &channelsPerBuffer);

    bufferList = calloc(1, getNumBytesForAudioBufferList(numBuffers));
    bufferList->mNumberBuffers = numBuffers; // have to set this because of validate inside allocateBuffersToAudioBufferList.

    return allocateBuffersToAudioBufferList(bufferList, bytesPerFrame, framesPerPacket, numBuffers, channelsPerBuffer);
}

AudioBufferList *cloneAudioBufferList(AudioBufferList *copyFrom) {
    AudioBufferList *audioList = malloc(getNumBytesForAudioBufferList(copyFrom->mNumberBuffers));
    audioList->mNumberBuffers = copyFrom->mNumberBuffers;
    for (int n = 0; n < copyFrom->mNumberBuffers; n++) {
        AudioBuffer *destinationAudioBuffer = &audioList->mBuffers[n];
        AudioBuffer *sourceAudioBuffer = &copyFrom->mBuffers[n];

        destinationAudioBuffer->mDataByteSize = sourceAudioBuffer->mDataByteSize;
        destinationAudioBuffer->mNumberChannels = sourceAudioBuffer->mNumberChannels;
        destinationAudioBuffer->mData = malloc(sourceAudioBuffer->mDataByteSize);
        memcpy(destinationAudioBuffer->mData, sourceAudioBuffer->mData, destinationAudioBuffer->mDataByteSize);
    }
    return audioList;
}

void freeAudioBufferListEx(AudioBufferList *audioBufferList, bool onStack) {
    for (int n = 0; n < audioBufferList->mNumberBuffers; n++) {
        AudioBuffer *currentAudioBuffer = &audioBufferList->mBuffers[n];
        free(currentAudioBuffer->mData);
    }

    // Caller may have allocated the list on the stack.
    if (!onStack) {
        free(audioBufferList);
    }
}

void freeAudioBufferList(AudioBufferList *audioBufferList) {
    freeAudioBufferListEx(audioBufferList, false);
}


bool shallowCopyBuffersEx(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList, enum AudioBufferListBufferHandling bufferHandling) {
    if (destinationAudioBufferList->mNumberBuffers < sourceAudioBufferList->mNumberBuffers) {
        NSLog(@"Cannot copy buffers over, destination audio buffer list is too small (shallowCopyBuffers)");
        return false;
    }

    destinationAudioBufferList->mNumberBuffers = sourceAudioBufferList->mNumberBuffers;
    for (int n = 0; n < sourceAudioBufferList->mNumberBuffers; n++) {
        AudioBuffer *destinationAudioBuffer = &destinationAudioBufferList->mBuffers[n];
        AudioBuffer *sourceAudioBuffer = &sourceAudioBufferList->mBuffers[n];

        if (bufferHandling == ABL_BUFFER_COPY) {
            destinationAudioBuffer->mData = sourceAudioBuffer->mData;
        } else if (bufferHandling == ABL_BUFFER_NULL_OUT) {
            destinationAudioBuffer->mData = NULL;
        } else if (bufferHandling == ABL_BUFFER_NOTHING) {
            // Do nothing.
        } else {
            NSLog(@"Invalid buffer handling mode");
        }
        destinationAudioBuffer->mDataByteSize = sourceAudioBuffer->mDataByteSize;
    }

    return true;
}

bool shallowCopyBuffers(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList) {
    return shallowCopyBuffersEx(destinationAudioBufferList, sourceAudioBufferList, ABL_BUFFER_COPY);
}

bool resetBuffers(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList) {
    if (destinationAudioBufferList->mNumberBuffers != sourceAudioBufferList->mNumberBuffers) {
        NSLog(@"Cannot reset buffers, destination audio buffer has a different number of buffers");
        return false;
    }

    shallowCopyBuffersEx(destinationAudioBufferList, sourceAudioBufferList, ABL_BUFFER_NOTHING);
    return true;
}



// Include destinationBufferMemorySize because otherwise our sanity checks are based on mDataByteSize which may
// be less than the size of the actual buffer which mData points to.
bool deepCopyBuffers(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList, UInt32 destinationBufferMemorySize) {
    if (destinationAudioBufferList->mNumberBuffers != sourceAudioBufferList->mNumberBuffers) {
        NSLog(@"Cannot copy buffers over, expected matching number of buffers (deepCopyBuffers)");
        return false;
    }

    for (int n = 0; n < sourceAudioBufferList->mNumberBuffers; n++) {
        AudioBuffer *destinationAudioBuffer = &destinationAudioBufferList->mBuffers[n];
        AudioBuffer *sourceAudioBuffer = &sourceAudioBufferList->mBuffers[n];

        if (destinationBufferMemorySize < sourceAudioBuffer->mDataByteSize) {
            NSLog(@"Memory size is too small, source is: %lu, destination is: %lu", sourceAudioBuffer->mDataByteSize, destinationBufferMemorySize);
            return false;
        }
        destinationAudioBuffer->mDataByteSize = sourceAudioBuffer->mDataByteSize;
        memcpy(destinationAudioBuffer->mData, sourceAudioBuffer->mData, sourceAudioBuffer->mDataByteSize);
    }

    return true;
}
