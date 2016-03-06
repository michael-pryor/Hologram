//
// Created by Michael Pryor on 06/03/2016.
//

#import <Foundation/Foundation.h>
#import "BlockingQueue.h"


@interface BlockingQueueTemporal : BlockingQueue
- (id)initWithName:(NSString *)name maxQueueSize:(uint)maxQueueSize trackerResetFrequencySeconds:(CFAbsoluteTime)resetFrequency minimumThreshold:(uint)minimumThreshold;

- (void)onSizeChange:(uint)count;
@end