//
//  Signal.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "Signal.h"
#import <Foundation/Foundation.h>

@implementation Signal {
    NSCondition * _condition;
    bool _flag;
}

- (id) initWithFlag: (bool)flag {
    self = [super init];
    if(self) {
        _condition = [[NSCondition alloc] init];
        _flag = flag;
    }
    return self;
}

- (id) init {
    return [self initWithFlag:false];
}

- (void) wait {
    [_condition lock];
    while (!_flag) {
        [_condition wait];
    }
    [_condition unlock];
}

- (void) signal {
    [_condition lock];
    _flag = true;
    [_condition signal];
    [_condition unlock];
}

- (void) clear {
    [_condition lock];
    _flag = false;
    [_condition unlock];
}

- (void) signalAll {
    [_condition lock];
    _flag = true;
    [_condition broadcast];
    [_condition unlock];
}

- (bool) isSignaled {
    [_condition lock];
    bool result = _flag;
    [_condition unlock];
    return result;
}

@end