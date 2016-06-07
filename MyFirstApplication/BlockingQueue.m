//
//  BlockingQueue.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import "BlockingQueue.h"
#import "TimedGapEventTracker.h"

@implementation BlockingQueue {
    NSCondition *_lock;
    NSMutableArray *_queue;
    Boolean _queueShutdown;
    unsigned long _maxQueueSize;
}
- (id)initWithName:(NSString *)humanName maxQueueSize:(unsigned long)maxSize{
    self = [super init];
    if (self) {
        _queue = [[NSMutableArray alloc] init];
        _lock = [[NSCondition alloc] init];
        _queueShutdown = false;
        _maxQueueSize = maxSize;
        _name = humanName;
    }
    return self;
}

- (id)init {
    return [self initWithName:@"queue" maxQueueSize:0];
}

- (uint)addObject:(id)obj atPosition:(int)position {
    if (_queueShutdown) {
        NSLog(@"(%@) Queue is shutdown, discarding insertion attempt", _name);
        return 0;
    }

    [_lock lock];

    if (obj == nil) {
        obj = [NSNull null];
        [_queue removeAllObjects];
        _queueShutdown = true;
    }


    if (_maxQueueSize > 0 && [_queue count] >= _maxQueueSize) {
        NSLog(@"(%@) Removing item from queue, breached maximum queue size of: %lu", _name, _maxQueueSize);

        // Remove object from start of array.
        [_queue removeObjectAtIndex:0];
    }

    // Add to end of array.
    if (position < 0) {
        [_queue addObject:obj];
    } else {
        // Will get NSRangeException if not enough space to accommodate insertObject:atIndex:
        if (position >= [_queue count]) {
            [_queue addObject:obj];
        } else {
            [_queue insertObject:obj atIndex:(uint) position];
        }
    }

    [self onSizeChange:[_queue count]];
    [_lock signal];

    uint returnVal = [_queue count];

    [_lock unlock];
    return returnVal;
}

- (uint)add:(id)obj {
    return [self addObject:obj atPosition:-1];
}

- (id)getImmediate:(double)timeoutSeconds {
    if (_queueShutdown) {
        NSLog(@"(%@) Queue is shutdown, rejecting receive attempt", _name);
        return nil;
    }

    [_lock lock];
    while (_queue.count == 0) {
        if (timeoutSeconds <= -1) {
            [_lock wait];
        } else if (timeoutSeconds == 0) {
            [_lock unlock];
            return nil;
        } else {
            if (![_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:timeoutSeconds]]) {
                [_lock unlock];
                return nil;
            }
        }
    }

    id retVal = _queue[0];

    if (retVal == [NSNull null]) {
        retVal = nil;
    }
    [self onSizeChange:[_queue count]];
    [_queue removeObjectAtIndex:0];

    [_lock unlock];

    return retVal;
}

- (id)peek {
    [_lock lock];

    id returnVal;
    if ([_queue count] > 0) {
        returnVal = _queue[0];
    } else {
        returnVal = nil;
    }

    [_lock unlock];
    return returnVal;
}

- (id)getImmediate {
    return [self getImmediate:0];
}

- (id)get {
    return [self getImmediate:-1];
}

- (void)onSizeChange:(uint)size {
    // option to override and respond to change in queue size.
}

- (id)getWithTimeout:(double)timeoutSeconds {
    return [self getImmediate:timeoutSeconds];
}

- (void)shutdown {
    [self add:nil];
}

- (void)restartQueue {
    [_lock lock];
    _queueShutdown = false;
    [_queue removeAllObjects];
    [_lock unlock];
}

- (void)clear {
    [_lock lock];
    [_queue removeAllObjects];
    [_lock unlock];
}

- (int)size {
    [_lock lock];
    int result = [_queue count];
    [_lock unlock];
    return result;
}

@end
