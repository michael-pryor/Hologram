//
// Created by Michael Pryor on 06/03/2016.
//

#import "BlockingQueueTemporal.h"
#import "TimedMinMaxTracker.h"

// This is a neat way of removing stale data from queues, and preventing latency from appearing if queue is partially full for extended periods of time.
@implementation BlockingQueueTemporal {
    TimedMinMaxTracker *_tracker;
    uint _minimumThreshold;
}
- (id)initWithName:(NSString *)name maxQueueSize:(uint)maxQueueSize trackerResetFrequencySeconds:(CFAbsoluteTime)resetFrequency minimumThreshold:(uint)minimumThreshold {
    self = [super initWithName:name maxQueueSize:maxQueueSize];
    if (self) {
        _tracker = [[TimedMinMaxTracker alloc] initWithResetFrequencySeconds:resetFrequency startingValue:_minimumThreshold];
        _minimumThreshold = minimumThreshold;
    }
    return self;
}

- (void)onSizeChange:(uint)count {
    TimedMinMaxTrackerResult result;
    bool populatedResult;

    [_tracker onValue:count result:&result hasResult:&populatedResult];
    if (populatedResult) {
        if (result.min > _minimumThreshold) {
            NSLog(@"(%@) CLEARING STALE queue which exceeded minimum threshold %u over last %.1f seconds (max = %u, min = %u)", [self name], _minimumThreshold, [_tracker getFrequencySeconds], result.max, result.min);
            [self clear];
        } else {
            NSLog(@"(%@) Successfully validated queue. It is within minimum threshold %u over last %.1f seconds (max = %u, min = %u)", [self name], _minimumThreshold, [_tracker getFrequencySeconds], result.max, result.min);
        }
    }
}
@end