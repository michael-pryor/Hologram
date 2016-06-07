//
// Created by Michael Pryor on 05/03/2016.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"
@import AudioToolbox;
#include "TimedCounter.h"

@class BlockingQueue;
@protocol SequenceGapNotification;
@protocol TimeInQueueNotification;

void printAudioBufferList(AudioBufferList *audioList, NSString *description);

@interface AudioDataContainer : NSObject
@property UInt32 numFrames;
@property AudioBufferList *audioList;

- (void)freeMemory;

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList;

- (id)initWithNumFrames:(UInt32)numFrames fromByteBuffer:(ByteBuffer *)byteBuffer audioFormat:(AudioStreamBasicDescription *)description;

- (ByteBuffer *)buildByteBufferWithLeftPadding:(uint)leftPadding;

- (void)incrementCounter:(TimedCounter *)counter;

- (bool)isValid;
@end

@protocol AudioDataPipeline
- (void)onNewAudioData:(AudioDataContainer *)audioData;
@end

BlockingQueue *buildAudioQueueEx(NSString *name, id <SequenceGapNotification> sequenceGapNotifier, id<TimeInQueueNotification> timeInQueueNotifier);

BlockingQueue *buildAudioQueue(NSString *name, id <SequenceGapNotification> sequenceGapNotifier);