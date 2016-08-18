//
// Created by Michael Pryor on 18/08/2016.
//

#import <Foundation/Foundation.h>


@interface MemoryAwareObjectContainer : NSObject
- (id)initWithConstructorBlock:(id (^)(void))constructorBlock;

- (void)reduceMemoryUsage;

- (id)get;
@end