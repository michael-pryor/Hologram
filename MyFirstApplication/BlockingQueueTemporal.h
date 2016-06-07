//
// Created by Michael Pryor on 06/03/2016.
//

#import <Foundation/Foundation.h>
#import "BlockingQueue.h"

@protocol SequenceGapNotification;


@interface BlockingQueueTemporal : BlockingQueue
- (id)initWithName:(NSString *)name maxQueueSize:(uint)maxQueueSize trackerResetFrequencySeconds:(CFAbsoluteTime)resetFrequency minimumThreshold:(uint)minimumThreshold sequenceGapNotifier:(id<SequenceGapNotification>)sequenceGapNotifier;
@end