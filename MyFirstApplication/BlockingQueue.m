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
    unsigned long _minQueueSizeLower;
    unsigned long _minQueueSizeUpper;
}
- (id)initWithMaxQueueSize:(unsigned long)maxSize {
    return [self initWithMaxQueueSize:maxSize minQueueSizeLowerBound:0 minQueueSizeUpperBound:0];
}

- (id)initWithMaxQueueSize:(unsigned long)maxSize minQueueSizeLowerBound:(unsigned long)minSizeLower minQueueSizeUpperBound:(unsigned long)minSizeUpper {
    self = [super init];
    if (self) {
        _queue = [[NSMutableArray alloc] init];
        _lock = [[NSCondition alloc] init];
        _queueShutdown = false;
        _maxQueueSize = maxSize;
        _minQueueSizeLower = minSizeLower;
        _minQueueSizeUpper = minSizeUpper;
    }
    return self;
}

- (id)init {
    return [self initWithMaxQueueSize:0];
}

- (uint)addObject:(id)obj atPosition:(int)position {
    if (_queueShutdown) {
        NSLog(@"Queue is shutdown, discarding send attempt");
        return 0;
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

    if ([_queue count] >= _minQueueSizeUpper) {
        [_lock signal];
    }
    uint returnVal = [_queue count];
    [_lock unlock];
    return returnVal;
}

- (uint)add:(id)obj {
    return [self addObject:obj atPosition:-1];
}

- (id)getImmediate:(double)timeoutSeconds {
    if (_queueShutdown) {
        NSLog(@"Queue is shutdown, rejecting receive attempt");
        return nil;
    }

    [_lock lock];
    while (_queue.count == 0 || _queue.count < _minQueueSizeLower) {
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

    [_queue removeObjectAtIndex:0];

    [_lock unlock];

    return retVal;
}

- (id)getImmediate {
    return [self getImmediate:0];
}

- (id)get {
    return [self getImmediate:-1];
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
