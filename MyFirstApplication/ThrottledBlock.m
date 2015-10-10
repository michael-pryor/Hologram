//
//  ThrottledBlock.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "ThrottledBlock.h"
#import "Timer.h"

@implementation ThrottledBlock {
    Timer *_timer;
}
- (id)initWithDefaultOutputFrequency:(CFAbsoluteTime)defaultOutputFrequency firingInitially:(Boolean)firingInitially {
    self = [super init];
    if (self) {
        _timer = [[Timer alloc] initWithFrequencySeconds:defaultOutputFrequency firingInitially:firingInitially];
    }
    return self;
}

- (void)reset {
    [_timer resetFrequency];
}

- (void)slowRate {
    [_timer doubleFrequencyValue];
}

- (Boolean)runBlock:(void (^)(void))theBlock {
    if ([_timer getState]) {
        theBlock();
        return true;
    } else {
        return false;
    }
}

- (CFAbsoluteTime)secondsFrequency {
    return [_timer secondsFrequency];
}

@end
