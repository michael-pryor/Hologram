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

- (id)initWithName:(NSString *)humanName maxQueueSize:(unsigned long)maxSize;

- (id)initWithName:(NSString *)humanName maxQueueSize:(unsigned long)maxSize minQueueSizeLowerBound:(unsigned long)minSizeLower minQueueSizeUpperBound:(unsigned long)minSizeUpper;

- (uint)add:(id)obj;

- (uint)addObject:(id)obj atPosition:(int)position;

- (id)peek;

- (id)get;

- (id)getImmediate;

- (id)getWithTimeout:(double)timeoutSeconds;

- (void)shutdown;

- (void)restartQueue;

- (void)clear;

- (int)size;

- (void)enableUniqueConstraint;

- (void)setupEventTracker:(CFAbsoluteTime)frequency;
@end
