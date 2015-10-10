//
//  BlockingQueue.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import "BlockingQueue.h"

@implementation BlockingQueue {
    NSCondition *_lock;
    NSMutableArray *_queue;
    Boolean _queueShutdown;
    unsigned long _maxQueueSize;
}
- (id)initWithMaxQueueSize:(unsigned long)maxSize {
    self = [super init];
    if (self) {
        _queue = [[NSMutableArray alloc] init];
        _lock = [[NSCondition alloc] init];
        _queueShutdown = false;
        _maxQueueSize = maxSize;
    }
    return self;
}

- (id)init {
    return [self initWithMaxQueueSize:0];
}

- (void)add:(id)obj {
    if (_queueShutdown) {
        NSLog(@"Queue is shutdown, discarding send attempt");
        return;
    }

    [_lock lock];

    if (obj == nil) {
        obj = [NSNull null];
        [_queue removeAllObjects];
        _queueShutdown = true;
    }

    if (_maxQueueSize > 0 && [_queue count] >= _maxQueueSize) {
        NSLog(@"Removing item from queue, breached maximum queue size of: %lu", _maxQueueSize);

        // Remove object from start of array.
        [_queue removeObjectAtIndex:0];
    }

    // Add to end of array.
    [_queue addObject:obj];

    [_lock signal];
    [_lock unlock];
}

- (id)getImmediate:(bool)immediate {
    if (_queueShutdown) {
        NSLog(@"Queue is shutdown, rejecting receive attempt");
        return nil;
    }

    [_lock lock];
    while (_queue.count == 0) {
        if (!immediate) {
            [_lock wait];
        } else {
            [_lock unlock];
            return nil;
        }
    }

    id retVal = _queue[0];

    if (retVal == [NSNull null]) {
        retVal = nil;
    }

    [_queue removeObjectAtIndex:0];
    [_lock unlock];

    return retVal;
}

- (id)getImmediate {
    return [self getImmediate:true];
}

- (id)get {
    return [self getImmediate:false];
}

- (unsigned long)getPendingAmount {
    [_lock lock];
    unsigned long size = _queue.count;
    [_lock unlock];
    return size;
}

- (void)shutdown {
    [self add:nil];
}

- (void)restartQueue {
    _queueShutdown = false;
    [_queue removeAllObjects];
}

- (void)clear {
    [_lock lock];
    [_queue removeAllObjects];
    [_lock unlock];
}

@end
