//
// Created by Michael Pryor on 06/03/2016.
//

#import "TimedMinMaxTracker.h"
#import "Timer.h"
#import <limits.h>

@implementation TimedMinMaxTracker {
    Timer *_resetTimer;
}
- (id)initWithResetFrequencySeconds:(CFAbsoluteTime)resetFrequency {
    self = [super init];
    if (self) {
        _resetTimer = [[Timer alloc] initWithFrequencySeconds:resetFrequency firingInitially:false];
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
            struct TimedMinMaxTrackerResult result = [self reset];
            if (result.max != UINT32_MAX) {
                *outResult = result;
                *outHasResult = true;
            } else {
                *outHasResult = false;
            }
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
        _min = UINT32_MAX;
        _max = 0;
        return result;
    }
}
@end