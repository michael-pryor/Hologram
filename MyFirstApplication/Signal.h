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

- (void)wait;

- (bool)signal;

- (bool)clear;

- (bool)signalAll;

- (bool)isSignaled;

- (int)incrementAndSignal;

- (int)incrementAndSignalAll;

- (int)decrement;
@end
