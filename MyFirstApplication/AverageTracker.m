//
// Created by Michael Pryor on 17/11/2015.
//

#import "AverageTracker.h"
#import "Timer.h"
#import "BlockingQueue.h"

@interface TrackedItem : NSObject
@end

@implementation TrackedItem {
    uint _value;
    Timer *_timerExpiry;
    bool _isExpired;
}

- (id)initWithValue:(uint)value expiry:(CFAbsoluteTime)expiryTime {
    self = [super init];
    if (self) {
        _value = value;
        _timerExpiry = [[Timer alloc] initWithFrequencySeconds:expiryTime firingInitially:false];
        _isExpired = false;
    }
    return self;
}

- (bool)isExpired {
    if (_isExpired) {
        return true;
    }

    _isExpired = [_timerExpiry getState];
    return _isExpired;
}

- (uint)getValue {
    return _value;
}
@end

@implementation AverageTracker {
    BlockingQueue *_blockingQueue;
    CFAbsoluteTime _expiryTime;
    uint _total;
}

- (id)initWithExpiry:(CFAbsoluteTime)expiryTime {
    self = [super init];
    if (self) {
        _expiryTime = expiryTime;
        _blockingQueue = [[BlockingQueue alloc] init];
    }
    return self;
}

- (void)expireItems {
    @synchronized (_blockingQueue) {
        while ([_blockingQueue size] > 0) {
            TrackedItem *item = [_blockingQueue peek];
            if ([item isExpired]) {
                [_blockingQueue getImmediate];
                _total -= [item getValue];
            } else {
                break;
            }
        }
    }
}

- (void)addValue:(uint)value {
    @synchronized (_blockingQueue) {
        [self expireItems];
        TrackedItem *item = [[TrackedItem alloc] initWithValue:value expiry:_expiryTime];
        [_blockingQueue add:item];
        _total += value;
    }

}

- (double)getWeightedAverage {
    @synchronized (_blockingQueue) {
        return ((double)_total / (double)[_blockingQueue size]);
    }
}

@end