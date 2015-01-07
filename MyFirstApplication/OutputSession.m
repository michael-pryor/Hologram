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
        
        // Starts off unconnected (closed).
        _signal = [[Signal alloc] initWithFlag:true];
    }
    return self;
}

- (void) sendPacket: (ByteBuffer*) packet {
    [_lock lock];
    
    ByteBuffer* prefixed;
    if(packet != (ByteBuffer*)[NSNull null]) {
        prefixed = [[ByteBuffer alloc] initWithSize:[packet bufferUsedSize] + sizeof(uint)];
        [prefixed addByteBuffer:packet includingPrefix:true];
    } else {
        prefixed = packet;
    }
    
    [_queue addObject:prefixed];
    [_lock signal];
    [_lock unlock];
}

- (void) confirmOpen {
    NSLog(@"Confirmation of open sent");
    [_signal clear];
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

- (bool) isClosed {
    return [_signal isSignaled];
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
