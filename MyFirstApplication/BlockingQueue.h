//
//  BlockingQueue.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>

@interface BlockingQueue : NSObject
- (id) init;
- (void) add:(id)obj;
- (id) get;
- (unsigned long) getPendingAmount;
- (id) getImmediate;
- (void) shutdown;
@end
