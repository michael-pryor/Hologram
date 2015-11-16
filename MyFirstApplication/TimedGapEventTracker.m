//
// Created by Michael Pryor on 16/11/2015.
//

#import "TimedGapEventTracker.h"
#import "Timer.h"


@implementation TimedGapEventTracker {
    uint _numEvents;
    Timer* _timer;
}
- (id)initWithResetFrequency:(CFAbsoluteTime)resetFrequency {
    self = [super init];
    if (self) {
        _timer = [[Timer alloc] initWithFrequencySeconds:resetFrequency firingInitially:false];
        _numEvents = 0;
    }
    return self;
}

- (uint)increment {
    @synchronized (_timer) {
        if ([_timer getState]) {
            uint retVal = _numEvents;
            _numEvents = 1;
            return retVal;
        }

        _numEvents += 1;
        [_timer reset];
        return 0;
    }
}
@end