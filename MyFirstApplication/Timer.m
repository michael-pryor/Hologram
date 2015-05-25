//
//  Timer.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "Timer.h"

@implementation Timer {
    CFAbsoluteTime _secondsEpoch;
}

- (id) initWithFrequencySeconds:(CFAbsoluteTime)frequency firingInitially:(Boolean)initialFire {
    self = [super init];
    if(self) {
        _secondsFrequency = frequency;
        _defaultSecondsFrequency = frequency;
        if(initialFire) {
            _secondsEpoch = 0;
        } else {
            _secondsEpoch = [Timer getSecondsEpoch];
        }

    }
    return self;
}

+ (CFAbsoluteTime) getSecondsEpoch {
    return CFAbsoluteTimeGetCurrent();
}

- (Boolean) getState {
    CFAbsoluteTime currentEpoch = [Timer getSecondsEpoch];
    
    if (currentEpoch - _secondsEpoch > [self secondsFrequency]) {
        _secondsEpoch = currentEpoch;
        return true;
    } else {
        return false;
    }
}

- (void) reset {
    _secondsEpoch = [Timer getSecondsEpoch];
}

- (void) resetFrequency {
    NSLog(@"Resetting frequency to default of %.2f", _defaultSecondsFrequency);
    _secondsFrequency = _defaultSecondsFrequency;
}

- (void) doubleFrequencyValue {
    float orig = _secondsFrequency;
    _secondsFrequency *= 2;
    NSLog(@"Slowed frequency from %.2f seconds to %.2f seconds", orig, _secondsFrequency);
}

@end
