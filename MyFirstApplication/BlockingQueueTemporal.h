//
// Created by Michael Pryor on 06/03/2016.
//

#import <Foundation/Foundation.h>
#import "BlockingQueue.h"

@protocol SequenceGapNotification;

// Track on average how long items are sat in the queue for, before being read.
@protocol TimeInQueueNotification
- (void)onTimeInQueueNotification:(uint)timeInQueueMs;
@end


@interface BlockingQueueTemporal : BlockingQueue
- (id)initWithName:(NSString *)name maxQueueSize:(uint)maxQueueSize trackerResetFrequencySeconds:(CFAbsoluteTime)resetFrequency minimumThreshold:(uint)minimumThreshold sequenceGapNotifier:(id<SequenceGapNotification>)sequenceGapNotifier timeInQueueNotifier:(id<TimeInQueueNotification>)timeInQueueNotifier timeInQueueNotifierFrequency:(CFAbsoluteTime)frequency;
@end