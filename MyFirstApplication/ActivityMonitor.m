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
    NSThread *_monitorThread;
    Signal *_actionSignal;
    Signal *_terminationSignal;
    Signal *_terminatedSignal;

    void (^_action)(void);

    float _backoffTimeSeconds;
}
- (id)initWithAction:(void (^)(void))action andBackoff:(float)backoffTimeSeconds {
    self = [super init];
    if (self) {
        _monitorThread = [[NSThread alloc] initWithTarget:self selector:@selector(entryPoint:) object:nil];
        [_monitorThread setName:@"ActivityMonitor"];
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

        if ([_terminationSignal isSignaled]) {
            break;
        }

        [NSThread sleepForTimeInterval:_backoffTimeSeconds];
        @try {
            _action();
        }
        @finally {
            // On termination will be 2, decrementing to 1,
            // meaning will not block on next wait.
            [_actionSignal decrement];
        }
    }
    NSLog(@"Activity monitor terminated");
    [_terminatedSignal signalAll];
}

- (void)performAction {
    [_actionSignal signal];
}

- (void)terminate {
    [_terminationSignal signal];
    [_actionSignal incrementAndSignal];
}

@end
