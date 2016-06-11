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
    void **_queuePtrs;
    uint _readPos;
    uint _writePos;

    Boolean _queueShutdown;
    unsigned long _maxQueueSize;
    unsigned long _queueSize;
}
- (id)initWithName:(NSString *)humanName maxQueueSize:(unsigned long)maxSize {
    self = [super init];
    if (self) {
        _lock = [[NSCondition alloc] init];
        _queuePtrs = malloc(sizeof(void *) * maxSize);
        [self clearNoLock];

        _queueShutdown = false;
        _maxQueueSize = maxSize;
        _name = humanName;
    }
    return self;
}

- (void)dealloc {
    free(_queuePtrs);
}

- (id)init {
    return [self initWithName:@"queue" maxQueueSize:1000];
}

- (uint)incrementIndex:(uint)currentIndex {
    uint newIndex = currentIndex + 1;
    if (newIndex >= _maxQueueSize) {
        return 0;
    }
    return newIndex;
}

- (void)clear {
    [_lock lock];
    [self clearNoLock];
    [_lock unlock];
}

- (void)clearNoLock {
    _writePos = 0; // clear queue.
    _readPos = 0;
    _queueSize = 0;
}

- (uint)add:(id)obj {
    if (_queueShutdown) {
        NSLog(@"(%@) Queue is shutdown, discarding insertion attempt", _name);
        return 0;
    }

    [_lock lock];

    if (obj == nil) {
        obj = [NSNull null];
        [self clearNoLock];
        _queueShutdown = true;
    }


    bool overwriting = false;
    if (_maxQueueSize > 0 && _queueSize >= _maxQueueSize) {
        NSLog(@"(%@) Removing item from queue, breached maximum queue size of: %lu", _name, _maxQueueSize);
        overwriting = true;
    }

    // Add to end of array.
    _queuePtrs[_writePos] = (void *) CFBridgingRetain(obj);
    _writePos = [self incrementIndex:_writePos];

    if (overwriting) {
        // The slot which will next be written to, currently contains the oldest data.
        _readPos = _writePos;
    } else {
        _queueSize++;
    }

    [self onSizeChange:_queueSize];
    [_lock signal];

    uint returnVal = _queueSize;

    [_lock unlock];
    return returnVal;
}

- (id)getImmediate:(double)timeoutSeconds {
    if (_queueShutdown) {
        NSLog(@"(%@) Queue is shutdown, rejecting receive attempt", _name);
        return nil;
    }

    [_lock lock];
    while (_queueSize == 0) {
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

    id retVal = CFBridgingRelease(_queuePtrs[_readPos]);

    if (retVal == [NSNull null]) {
        retVal = nil;
    }
    _readPos = [self incrementIndex:_readPos];
    _queueSize--;
    [self onSizeChange:_queueSize];


    [_lock unlock];

    return retVal;
}

- (id)peek {
    [_lock lock];

    id returnVal;
    if (_queueSize > 0) {
        returnVal = (__bridge NSObject *) (_queuePtrs[_readPos]);
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
    [self clearNoLock];
    [_lock unlock];
}

- (int)size {
    [_lock lock];
    uint result = _queueSize;
    [_lock unlock];
    return result;
}

@end
