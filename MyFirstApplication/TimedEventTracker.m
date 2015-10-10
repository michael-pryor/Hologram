//
//  TimedEventTracker.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "TimedEventTracker.h"
#import "Timer.h"
#import "EventTracker.h"

@implementation TimedEventTracker {
    EventTracker *_eventTracker;
    Timer *_timer;
}

- (id)initWithMaxEvents:(uint)maxEvents timePeriod:(CFAbsoluteTime)defaultOutputFrequency {
    self = [super init];
    if (self) {
        _timer = [[Timer alloc] initWithFrequencySeconds:defaultOutputFrequency firingInitially:false];
        _eventTracker = [[EventTracker alloc] initWithMaxEvents:maxEvents];
    }
    return self;
}

- (Boolean)increment {
    if ([_timer getState]) {
        [_eventTracker reset];
    } else if ([_eventTracker getNumEvents] == 0) {
        [_timer reset];
    }

    return [_eventTracker increment];
}

- (void)reset {
    [_timer reset];
    [_eventTracker reset];
}

- (void)setTimePeriod:(CFAbsoluteTime)outputFrequency {
    [_timer setSecondsFrequency:outputFrequency];
}

- (void)resetTimePeriod {
    [_timer resetFrequency];
}

@end
