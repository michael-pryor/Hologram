//
// Created by Michael Pryor on 06/03/2016.
//

#import "BlockingQueueTemporal.h"
#import "TimedMinMaxTracker.h"
#import "SequenceDecodingPipe.h"
#import "Timer.h"
#import "AverageTrackerLimitedSize.h"

// This is a neat way of removing stale data from queues, and preventing latency from appearing if queue is partially full for extended periods of time.
@implementation BlockingQueueTemporal {
    TimedMinMaxTracker *_tracker;
    uint _minimumThreshold;
    id<SequenceGapNotification> _sequenceGapNotifier;
    BlockingQueue *_timeTrackers;
    AverageTrackerLimitedSize *_averageTimeInQueueTrackerMs;
}
- (id)initWithName:(NSString *)name maxQueueSize:(uint)maxQueueSize trackerResetFrequencySeconds:(CFAbsoluteTime)resetFrequency minimumThreshold:(uint)minimumThreshold sequenceGapNotifier:(id<SequenceGapNotification>)sequenceGapNotifier {
    self = [super initWithName:name maxQueueSize:maxQueueSize];
    if (self) {
        _tracker = [[TimedMinMaxTracker alloc] initWithResetFrequencySeconds:resetFrequency startingValue:_minimumThreshold];
        _minimumThreshold = minimumThreshold;
        _sequenceGapNotifier = sequenceGapNotifier;

        // Track average time in queue over last 5 seconds.
        _averageTimeInQueueTrackerMs = [[AverageTrackerLimitedSize alloc] initWithMaxSize:10];
        _timeTrackers = [[BlockingQueue alloc] init];
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
            if (_sequenceGapNotifier != nil) {
                [_sequenceGapNotifier onSequenceGap:result.min fromSender:self];
            }
            [self clear];
        } else {
            NSLog(@"(%@) Successfully validated queue (%2.fms average time). It is within minimum threshold %u over last %.1f seconds (max = %u, min = %u)", [self name], [_averageTimeInQueueTrackerMs getWeightedAverage], _minimumThreshold, [_tracker getFrequencySeconds], result.max, result.min);
        }
    }
}

- (uint)addObject:(id)obj atPosition:(int)position {
    [_timeTrackers addObject:[[Timer alloc] init] atPosition:position];
    return [super addObject:obj atPosition:position];
}

-(id)getImmediate:(double)timeoutSeconds {
    id result = [super getImmediate:timeoutSeconds];
    if (result == nil) {
        return nil;
    }
    Timer * _timer = [_timeTrackers get];
    [_averageTimeInQueueTrackerMs addValue:(uint)([_timer getSecondsSinceLastTick] * 1000.0)];
    return result;
}
@end