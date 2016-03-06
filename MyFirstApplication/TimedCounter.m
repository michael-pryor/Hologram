//
// Created by Michael Pryor on 05/03/2016.
//

#import "TimedCounter.h"
#import "Timer.h"


@implementation TimedCounter {
    Timer *_timer;

    uint _amount;
}
- (id)initWithTimer:(Timer*)timer {
    self = [super init];
    if (self) {
        _timer = timer;
        _lastTotal = 0;
    }
    return self;
}

- (id)initWithFrequencySeconds:(CFAbsoluteTime)frequencySeconds {
    return [self initWithTimer:[[Timer alloc] initWithFrequencySeconds:frequencySeconds firingInitially:false]];
}

- (bool)incrementBy:(uint)amount {
    @synchronized(_timer) {
        _amount += amount;
        if ([_timer getState]) {
            _lastTotal = _amount;
            _amount = 0;
            return true;
        }
        return false;
    }
}
@end