//
//  BlockingQueue.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>

@interface BlockingQueue : NSObject
- (id)init;

- (id)initWithMaxQueueSize:(unsigned long)maxSize;

- (id)initWithMaxQueueSize:(unsigned long)maxSize minQueueSizeLowerBound:(unsigned long)minSizeLower minQueueSizeUpperBound:(unsigned long)minSizeUpper;

- (uint)add:(id)obj;

- (uint)addObject:(id)obj atPosition:(int)position;

- (id)get;

- (id)getImmediate;

- (id)getWithTimeout:(double)timeoutSeconds;

- (void)shutdown;

- (void)restartQueue;

- (void)clear;

- (int)size;
@end
