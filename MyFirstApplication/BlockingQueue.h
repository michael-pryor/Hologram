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

- (id)get;

- (unsigned long)getPendingAmount;

- (id)getImmediate;

- (void)shutdown;

- (void)restartQueue;
@end
