//
//  Timer.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "Timer.h"
#import "Random.h"

@implementation Timer {
    CFAbsoluteTime _secondsEpoch;
    CFAbsoluteTime _secondsJitter;
    CFAbsoluteTime _currentJitterValue;
}

// Use this if all we want to use is getSecondsSinceLastTick, none of the tick logic.
- (id)init {
    return [self initWithFrequencySeconds:0 firingInitially:false];
}

- (id)initWithFrequencySeconds:(CFAbsoluteTime)frequency firingInitially:(Boolean)initialFire {
    return [self initWithFrequencySeconds:frequency firingInitially:initialFire jitterSeconds:0];
}

- (id)initWithFrequencySeconds:(CFAbsoluteTime)frequency firingInitially:(Boolean)initialFire jitterSeconds:(CFAbsoluteTime)jitter {
    self = [super init];
    if (self) {
        _secondsFrequency = frequency;
        _secondsJitter = jitter;
        _defaultSecondsFrequency = frequency;
        if (initialFire) {
            _secondsEpoch = 0;
        } else {
            _secondsEpoch = [Timer getSecondsEpoch];
        }

    }
    return self;
}

- (void)updateJitter {
    if (_secondsJitter <= 0) {
        _currentJitterValue = 0;
        return;
    }

    _currentJitterValue = [Random randomDoubleBetween:0 and:_secondsJitter];
}

+ (CFAbsoluteTime)getSecondsEpoch {
    return CFAbsoluteTimeGetCurrent();
}

- (Boolean)getState {
    if ([self getSecondsSinceLastTick] > [self secondsFrequency] + _currentJitterValue) {
        _secondsEpoch = [Timer getSecondsEpoch];
        [self updateJitter];
        return true;
    } else {
        return false;
    }
}

- (CFAbsoluteTime)getSecondsSinceLastTick {
    return [Timer getSecondsEpoch] - _secondsEpoch;
}

- (void)blockUntilNextTick {
    if (_secondsEpoch == 0) {
        _secondsEpoch = [Timer getSecondsEpoch] - _secondsFrequency;
    }

    CFAbsoluteTime timeSinceLastTick = [self getSecondsSinceLastTick];
    CFAbsoluteTime timeRemaining = _secondsFrequency - timeSinceLastTick;
    if (timeRemaining > 0) {
        [NSThread sleepForTimeInterval:timeRemaining];
    }
    _secondsEpoch = [Timer getSecondsEpoch];
}

- (void)reset {
    _secondsEpoch = [Timer getSecondsEpoch];
}

- (void)resetFrequency {
    NSLog(@"Resetting frequency to default of %.2f", _defaultSecondsFrequency);
    _secondsFrequency = _defaultSecondsFrequency;
}

- (void)doubleFrequencyValue {
    /* float orig = _secondsFrequency;
     _secondsFrequency *= 2;
     NSLog(@"Slowed frequency from %.2f seconds to %.2f seconds", orig, _secondsFrequency);*/
}

@end
