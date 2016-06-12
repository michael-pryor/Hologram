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
    id <SequenceGapNotification> _sequenceGapNotifier;
    id <TimeInQueueNotification> _timeInQueueNotifier;

    Timer *_timeInQueueNotifierTimer;

    BlockingQueue *_timeTrackers;
    AverageTrackerLimitedSize *_averageTimeInQueueTrackerMs;
    uint _maxQueueSize;
}
- (id)initWithName:(NSString *)name maxQueueSize:(uint)maxQueueSize trackerResetFrequencySeconds:(CFAbsoluteTime)resetFrequency minimumThreshold:(uint)minimumThreshold sequenceGapNotifier:(id <SequenceGapNotification>)sequenceGapNotifier timeInQueueNotifier:(id <TimeInQueueNotification>)timeInQueueNotifier timeInQueueNotifierFrequency:(CFAbsoluteTime)frequency {
    self = [super initWithName:name maxQueueSize:maxQueueSize];
    if (self) {
        _minimumThreshold = minimumThreshold;
        _tracker = [[TimedMinMaxTracker alloc] initWithResetFrequencySeconds:resetFrequency];

        _sequenceGapNotifier = sequenceGapNotifier;
        _timeInQueueNotifier = timeInQueueNotifier;

        _maxQueueSize = maxQueueSize;

        // Track average time in the queue.
        if (timeInQueueNotifier != nil) {
            _timeInQueueNotifierTimer = [[Timer alloc] initWithFrequencySeconds:frequency firingInitially:true];
            _averageTimeInQueueTrackerMs = [[AverageTrackerLimitedSize alloc] initWithMaxSize:125];
            _timeTrackers = [[BlockingQueue alloc] initWithName:[NSString stringWithFormat:@"[time tracker] %@", name] maxQueueSize:_maxQueueSize];
        }
    }
    return self;
}

- (void)onSizeChange:(uint)count {
    TimedMinMaxTrackerResult result;
    bool populatedResult;

    if (_timeTrackers != nil) {
        if ([_timeInQueueNotifierTimer getState]) {
            double averageTimeInQueue = [_averageTimeInQueueTrackerMs getWeightedAverage];
            if (_timeInQueueNotifier != nil) {
                [_timeInQueueNotifier onTimeInQueueNotification:(uint) averageTimeInQueue];
            }
        }
    }

    [_tracker onValue:count result:&result hasResult:&populatedResult];
    if (populatedResult) {
        if (result.min > _minimumThreshold) {
            NSLog(@"(%@) CLEARING STALE queue which exceeded minimum threshold %u over last %.1f seconds (max = %u, min = %u)", [self name], _minimumThreshold, [_tracker getFrequencySeconds], result.max, result.min);
            if (_sequenceGapNotifier != nil) {
                [_sequenceGapNotifier onSequenceGap:result.min fromSender:self];
            }
            [self clear];
        } else {
            NSLog(@"(%@) Successfully validated queue. It is within minimum threshold %u over last %.1f seconds (max = %u, min = %u)", [self name], _minimumThreshold, [_tracker getFrequencySeconds], result.max, result.min);
        }
    }
}

- (uint)add:(id)obj {
    if (_timeTrackers != nil) {
        [_timeTrackers add:[[Timer alloc] init]];
    }
    return [super add:obj];
}

- (id)getImmediate:(double)timeoutSeconds {
    id result = [super getImmediate:timeoutSeconds];

    if (_timeTrackers != nil) {
        if (result == nil) {
            return nil;
        }

        Timer *_timer = [_timeTrackers get];
        [_averageTimeInQueueTrackerMs addValue:(uint) ([_timer getSecondsSinceLastTick] * 1000.0)];
    }
    return result;
}

- (void)clear {
    // We clear like this to solve synchronization issues.
    if (_timeTrackers != nil) {
        int numCleared = 0;
        while ([self getImmediate] != nil && numCleared < _maxQueueSize) {
            numCleared++;
        }
        return;
    }

    // Otherwise, we can just clear normally.
    [super clear];
}
@end