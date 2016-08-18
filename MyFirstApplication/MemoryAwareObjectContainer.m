//
// Created by Michael Pryor on 18/08/2016.
//

#import "MemoryAwareObjectContainer.h"


@implementation MemoryAwareObjectContainer {
    id _object;

    id (^_constructorBlock)(void);
}
- (id)initWithConstructorBlock:(id (^)(void))constructorBlock {
    self = [super init];
    if (self) {
        _constructorBlock = constructorBlock;
    }
    return self;
}

- (id)get {
    @synchronized(self) {
        if (_object == nil) {
            NSLog(@"** Building object ***");
            _object = _constructorBlock();
        }
        return _object;
    }
}

- (void)reduceMemoryUsage {
    @synchronized (self) {
        _object = nil;
    }
}
@end