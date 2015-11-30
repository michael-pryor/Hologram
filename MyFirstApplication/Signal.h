//
//  Signal.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import <Foundation/Foundation.h>

@interface Signal : NSObject
- (id)initWithFlag:(bool)flag;

- (id)init;

- (bool)wait;

- (bool)signal;

- (bool)clear;

- (bool)signalAll;

- (void)dummySignalAll;

- (bool)isSignaled;

- (int)incrementAndSignal;

- (int)incrementAndSignalAll;

- (int)decrement;
@end
