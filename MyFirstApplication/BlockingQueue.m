//
//  BlockingQueue.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import "BlockingQueue.h"

@implementation BlockingQueue {
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

- (void) add:(id)obj {
    if(_queueShutdown) {
        NSLog(@"Queue is shutdown, discarding send attempt");
        return;
    }
    
    [_lock lock];
    
    if(obj == nil) {
        obj = [NSNull null];
        [_queue removeAllObjects];
        _queueShutdown = true;
    }
    
    [_queue addObject:obj];
    [_lock signal];
    [_lock unlock];
}

- (id) get {
    if(_queueShutdown) {
        NSLog(@"Queue is shutdown, rejecting receive attempt");
        return nil;
    }
    
    [_lock lock];
    while (_queue.count == 0) {
        [_lock wait];
    }
    
    id retVal = _queue[0];
    
    if(retVal == [NSNull null]) {
        retVal = nil;
    }
    
    [_queue removeObjectAtIndex:0];
    [_lock unlock];
    return retVal;
}

- (void)shutdown {
    [self add: nil];
}

@end
