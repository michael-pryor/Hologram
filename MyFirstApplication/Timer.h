//
//  Timer.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import <Foundation/Foundation.h>

@interface Timer : NSObject
@property(atomic) CFAbsoluteTime secondsFrequency;
@property(readonly) CFAbsoluteTime defaultSecondsFrequency;

- (id)init;

- (id)initWithFrequencySeconds:(CFAbsoluteTime)frequency firingInitially:(Boolean)initialFire;

- (id)initWithFrequencySeconds:(CFAbsoluteTime)frequency firingInitially:(Boolean)initialFire jitterSeconds:(CFAbsoluteTime)jitter;

- (Boolean)getState;

- (void)reset;

- (void)resetFrequency;

- (void)doubleFrequencyValue;

- (CFAbsoluteTime)getSecondsSinceLastTick;

- (void)blockUntilNextTick;

+ (CFAbsoluteTime)getSecondsEpoch;
@end
