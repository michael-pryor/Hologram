//
//  OutputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "OutputSession.h"
#import "Signal.h"
#import <Foundation/Foundation.h>

@implementation OutputSession {
    NSCondition * _lock;
    Signal * _signal;
    NSMutableArray * _queue;
}
- (id) init {
    self = [super init];
    if(self) {
	    _queue = [[NSMutableArray alloc] init];
        _lock =  [[NSCondition alloc] init];
        _signal = [[Signal alloc] init];
    }
    return self;
}

- (void) sendPacket: (ByteBuffer*) packet {
    [_lock lock];
    [_queue addObject:packet];
    [_lock signal];
    [_lock unlock];
}

- (void) closeConnection {
    [self sendPacket: (ByteBuffer*)[NSNull null]];
    NSLog(@"Waiting for close confirmation..");
    [_signal wait];

}

- (void) confirmClosure {
    NSLog(@"Confirmation of closure sent");
    [_signal signalAll];
}


- (ByteBuffer*) processPacket {
    [_lock lock];
    while (_queue.count == 0)
    {
        [_lock wait];
    }

    ByteBuffer* retVal = (ByteBuffer*)_queue[0];
    
    if(retVal == (ByteBuffer*)[NSNull null]) {
        retVal = nil;
    }
    
    [_queue removeObjectAtIndex:0];
    [_lock unlock];
    return retVal;
}


@end
