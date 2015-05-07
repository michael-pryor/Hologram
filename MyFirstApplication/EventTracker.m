//
//  NSObject+EventTracker.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/04/2015.
//
//

#import "EventTracker.h"

@implementation EventTracker {
    uint _numEvents;
    uint _maxEvents;
}
- (id) initWithMaxEvents:(uint)maxEvents {
    self = [super init];
    if(self) {
        _numEvents = 0;
        _maxEvents = maxEvents;
    }
    return self;
}
- (Boolean) increment {
    _numEvents += 1;
    return _numEvents >= _maxEvents;
}
- (void) reset {
    _numEvents = 0;
}
- (uint) getNumFailures {
    return _numEvents;
}
@end
