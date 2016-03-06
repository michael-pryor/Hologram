//
// Created by Michael Pryor on 22/02/2016.
//

@import AudioToolbox;

enum AudioBufferListBufferHandling {
    ABL_BUFFER_NULL_OUT,
    ABL_BUFFER_COPY,
    ABL_BUFFER_NOTHING,
    ABL_BUFFER_ALLOCATE_NEW
};

AudioBufferList initializeAudioBufferList();

AudioBufferList *allocateBuffersToAudioBufferList(AudioBufferList *destinationAudioBufferList, UInt32 bytesPerFrame, UInt32 framesPerPacket, UInt32 numBuffers, UInt32 channelsPerBuffer);

AudioBufferList *allocateBuffersToAudioBufferListEx(AudioBufferList *destinationAudioBufferList, UInt32 bytesPerFrame, UInt32 framesPerPacket, UInt32 numPackets, UInt32 channelsPerFrame, bool channelsInterleaved);

AudioBufferList *allocateAudioBufferList(UInt32 bytesPerFrame, UInt32 framesPerPacket, UInt32 numPackets, UInt32 channelsPerFrame, bool channelsInterleaved);

AudioBufferList *cloneAudioBufferList(AudioBufferList *copyFrom);

void freeAudioBufferListEx(AudioBufferList *audioBufferList, bool onStack);

void freeAudioBufferList(AudioBufferList *audioBufferList);

bool shallowCopyBuffersEx(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList, enum AudioBufferListBufferHandling bufferHandling);

bool shallowCopyBuffers(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList);

bool resetBuffers(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList);

bool deepCopyBuffers(AudioBufferList *destinationAudioBufferList, AudioBufferList *sourceAudioBufferList, UInt32 destinationBufferMemorySize);

AudioClassDescription *getAudioClassDescriptionWithType(UInt32 type, UInt32 manufacturer);

AudioBufferList *initializeAudioBufferListHeap(UInt32 numBuffers);

AudioBufferList *initializeAudioBufferListHeapSingle(UInt32 byteSize, UInt32 numberChannels);

UInt32 getNumBytesForAudioBufferList(UInt32 numBuffers);

AudioBufferList initializeAudioBufferListSingle(UInt32 byteSize, UInt32 numberChannels);