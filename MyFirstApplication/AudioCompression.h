//
// Created by Michael Pryor on 21/02/2016.
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
@import AudioToolbox;

void printAudioBufferList(AudioBufferList *audioList, NSString *description);

@interface AudioDataContainer : NSObject
@property UInt32 numFrames;
@property AudioBufferList *audioList;

- (void)freeMemory;

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList;

- (id)initFromByteBuffer:(ByteBuffer *)byteBuffer audioFormat:(AudioStreamBasicDescription *)description;

- (ByteBuffer *)buildByteBufferWithLeftPadding:(uint)leftPadding;
@end

@protocol AudioDataPipeline
- (void)onNewAudioData:(AudioDataContainer *)audioData;
@end

@interface AudioCompression : NSObject <AudioDataPipeline, NewPacketDelegate>
- (id)initWithAudioFormat:(AudioStreamBasicDescription)audioFormat outputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding;

- (AudioDataContainer *)getPendingDecompressedData;

- (AudioDataContainer *)getUncompressedItem;

- (AudioDataContainer *)getCompressedItem;

- (void)initialize;

- (void)reset;

- (void)terminate;
@end