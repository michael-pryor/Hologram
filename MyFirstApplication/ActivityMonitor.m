//
//  ConnectionMonitor.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 03/05/2015.
//
//

#import "ActivityMonitor.h"
#import "Signal.h"

@implementation ActivityMonitor {
    NSThread* _monitorThread;
    Signal* _actionSignal;
    Signal * _terminationSignal;
    Signal * _terminatedSignal;
    void (^_action)(void);
    float _backoffTimeSeconds;
}
- (id)initWithAction:(void (^)(void))action andBackoff:(float)backoffTimeSeconds {
    self = [super init];
    if(self) {
        _monitorThread = [[NSThread alloc] initWithTarget:self selector:@selector(entryPoint:) object:nil];
        _actionSignal = [[Signal alloc] initWithFlag:false];
        _terminationSignal = [[Signal alloc] initWithFlag:false];
        _terminatedSignal = [[Signal alloc] initWithFlag:false];
        _action = action;
        _backoffTimeSeconds = backoffTimeSeconds;
        [_monitorThread start];
    }
    return self;
}

- (void)entryPoint:(id)arg {
    NSLog(@"Activity monitor started");
    while (![_terminationSignal isSignaled]) {
        [_actionSignal wait];
        
        if([_terminationSignal isSignaled]) {
            break;
        }
        
        [NSThread sleepForTimeInterval:_backoffTimeSeconds];
        @try {
            _action();
        }
        @finally {
            [_actionSignal clear];
        }
    }
    NSLog(@"Activity monitor terminated");
    [_terminatedSignal signalAll];
}

- (void)performAction {
    [_actionSignal signal];
}

- (void)terminate {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Small change we'l have to loop round twice,
        // that avoids race condition.
        while(![_terminatedSignal isSignaled]) {
            [_terminationSignal signal];
            [_actionSignal signal];
            [NSThread sleepForTimeInterval:0.1];
        }
    });
}

@end
