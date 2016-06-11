//
//  BlockingQueue.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>

@interface BlockingQueue : NSObject
@property(readonly) NSString *name;

- (id)init;

- (id)initWithName:(NSString *)humanName maxQueueSize:(unsigned long)maxSize;

- (uint)add:(id)obj;

- (id)peek;

- (id)get;

- (id)getImmediate;

- (id)getWithTimeout:(double)timeoutSeconds;

- (void)shutdown;

- (void)restartQueue;

- (void)clear;

- (int)size;

// Protected methods:
- (void)onSizeChange:(uint)size;

- (id)getImmediate:(double)timeoutSeconds;
@end
