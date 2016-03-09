//
// Created by Michael Pryor on 09/03/2016.
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"

@protocol SequenceGapNotification
- (void)onSequenceGap:(uint)gapSize fromSender:(id)sender;
@end

@interface SequenceDecodingPipe : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession sequenceGapNotification:(id <SequenceGapNotification>)sequenceGapNotification;
@end