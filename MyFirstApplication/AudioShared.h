//
// Created by Michael Pryor on 05/03/2016.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"
@import AudioToolbox;
#include "TimedCounter.h"

void printAudioBufferList(AudioBufferList *audioList, NSString *description);

@interface AudioDataContainer : NSObject
@property UInt32 numFrames;
@property AudioBufferList *audioList;

- (void)freeMemory;

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList;

- (id)initFromByteBuffer:(ByteBuffer *)byteBuffer audioFormat:(AudioStreamBasicDescription *)description;

- (ByteBuffer *)buildByteBufferWithLeftPadding:(uint)leftPadding;

+ (void)handleTimedCounter:(TimedCounter *)counter description:(NSString *)description incrementContainer:(AudioDataContainer *)container;
@end

@protocol AudioDataPipeline
- (void)onNewAudioData:(AudioDataContainer *)audioData;
@end