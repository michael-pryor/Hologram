//
//  Signal.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "Signal.h"

@implementation Signal {
    NSCondition *_condition;
    int _counter;
}

- (id)initWithFlag:(bool)flag {
    self = [super init];
    if (self) {
        _condition = [[NSCondition alloc] init];
        if (flag) {
            _counter = 1;
        } else {
            _counter = 0;
        }
    }
    return self;
}

- (id)init {
    return [self initWithFlag:false];
}

- (void)wait {
    [_condition lock];
    while (_counter == 0) {
        [_condition wait];
    }
    [_condition unlock];
}

// Return true if state has changed.
- (bool)signal {
    [_condition lock];
    bool ret = _counter < 1;
    if (ret) {
        _counter = 1;
        [_condition signal];
    }
    [_condition unlock];
    return ret;
}

// Return true if state has changed.
- (bool)clear {
    [_condition lock];
    bool ret = _counter > 0;
    if (ret) {
        _counter = 0;
    }
    [_condition unlock];
    return ret;
}

// Return true if state has changed.
- (bool)signalAll {
    [_condition lock];
    bool ret = _counter < 1;
    if (ret) {
        _counter = 1;
        [_condition broadcast];
    }
    [_condition unlock];
    return ret;
}

- (bool)isSignaled {
    [_condition lock];
    bool result = _counter > 0;
    [_condition unlock];
    return result;
}

- (int)incrementAndSignal {
    [_condition lock];
    int ret = _counter;
    _counter++;
    [_condition signal];

    [_condition unlock];
    return ret;
}


- (int)incrementAndSignalAll {
    [_condition lock];
    int ret = _counter;
    _counter++;
    [_condition broadcast];

    [_condition unlock];
    return ret;
}

- (int)decrement {
    [_condition lock];
    int ret = _counter;
    _counter--;
    [_condition unlock];
    return ret;
}

@end
