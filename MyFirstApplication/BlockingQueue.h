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

- (void)add:(id)obj;

- (void)addObject:(id)obj atPosition:(int)position;

- (id)get;

- (id)getImmediate;

- (void)shutdown;

- (void)restartQueue;

- (void)clear;

- (int)size;
@end
