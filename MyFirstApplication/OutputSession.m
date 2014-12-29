//
//  OutputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "OutputSession.h"

@implementation OutputSession
@synthesize _lock;
- (id) init {
    self = [super init];
    if(self) {
	    queue = [NSMutableArray new];
    }
    return self;
}

- (void) sendPacket: (ByteBuffer*) packet {
    [_lock lock];
    [queue addObject:packet];
    [_lock signal];
    [_lock unlock];
}

- (ByteBuffer*) processPacket {
    [_lock lock];
    while (queue.count == 0)
    {
        [_lock wait];
    }
    ByteBuffer* retVal = (ByteBuffer*)queue[0];
    [queue removeObjectAtIndex:0];
    [_lock unlock];
    return retVal;
}


@end
