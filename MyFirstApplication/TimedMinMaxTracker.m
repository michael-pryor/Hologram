//
// Created by Michael Pryor on 06/03/2016.
//

#import "TimedMinMaxTracker.h"
#import "Timer.h"


@implementation TimedMinMaxTracker {
    Timer *_resetTimer;
}
- (id)initWithResetFrequencySeconds:(CFAbsoluteTime)resetFrequency startingValue:(uint)startingValue {
    self = [super init];
    if (self) {
        _resetTimer = [[Timer alloc] initWithFrequencySeconds:resetFrequency firingInitially:false];
        _startingValue = startingValue;
    }
    return self;
}

- (CFAbsoluteTime)getFrequencySeconds {
    return [_resetTimer secondsFrequency];
}

- (void)onValue:(uint)value result:(TimedMinMaxTrackerResult*)outResult hasResult:(bool*)outHasResult {
    @synchronized (self) {
        if (value < _min) {
            _min = value;
        }
        if (value > _max) {
            _max = value;
        }
        if ([_resetTimer getState]) {
            *outResult = [self reset];
            *outHasResult = true;
            return;
        }
    }
    *outHasResult = false;
}

- (TimedMinMaxTrackerResult)reset {
    @synchronized (self) {
        struct TimedMinMaxTrackerResult result;
        result.max = _max;
        result.min = _min;
        _min = _startingValue;
        _max = _startingValue;
        return result;
    }
}
@end