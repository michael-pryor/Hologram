//
//  OutputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "OutputSessionTcp.h"
#import <Foundation/Foundation.h>

@implementation OutputSessionTcp {
    NSCondition * _lock;
    NSMutableArray * _queue;
    Boolean _queueShutdown;
}
- (id) init {
    self = [super init];
    if(self) {
	    _queue = [[NSMutableArray alloc] init];
        _lock =  [[NSCondition alloc] init];
        _queueShutdown = false;
    }
    return self;
}

- (void) sendPacket: (ByteBuffer*) packet {
    if(_queueShutdown) {
        NSLog(@"TCP send queue is shutdown, discarding send attempt");
        return;
    }
    
    [_lock lock];
    
    ByteBuffer* prefixed;
    if(packet != nil) {
        prefixed = [[ByteBuffer alloc] initWithSize:[packet bufferUsedSize] + sizeof(uint)];
        [prefixed addByteBuffer:packet includingPrefix:true];
    } else {
        prefixed = (ByteBuffer*)[NSNull null];
        [_queue removeAllObjects];
        _queueShutdown = true;
    }

    [_queue addObject:prefixed];
    [_lock signal];
    [_lock unlock];
}

- (ByteBuffer*) processPacket {
    if(_queueShutdown) {
        NSLog(@"TCP send queue is shutdown, rejecting receive attempt");
        return nil;
    }
    
    [_lock lock];
    while (_queue.count == 0) {
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
