//
// Created by Michael Pryor on 11/06/2016.
//

#import "ReadWriteLock.h"
#import <pthread.h>

@implementation ReadWriteLock {
    pthread_rwlock_t _lock;
}
- (id)init {
    self = [super init];
    if (self) {
        int result = pthread_rwlock_init(&_lock, nil);
        [self validate:result];
    }
    return self;
}

- (void)validate:(int)result {
    if (result != 0) {
        NSLog(@"Failed to initialize read/write lock: %d", result);
        [NSException raise:@"Read/write lock failure" format:@"Failure with result: %d", result];
    }
}

- (void)lockForReading {
    int result = pthread_rwlock_rdlock(&_lock);
    [self validate:result];
}

- (void)lockForWriting {
    int result = pthread_rwlock_wrlock(&_lock);
    [self validate:result];
}

- (void)unlock {
    int result = pthread_rwlock_unlock(&_lock);
    [self validate:result];
}

- (void)dealloc {
    int result = pthread_rwlock_destroy(&_lock);
    [self validate:result];
}
@end