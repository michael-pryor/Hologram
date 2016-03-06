//
// Created by Michael Pryor on 06/03/2016.
//

#import <Foundation/Foundation.h>
#import "TimedCounter.h"


@interface TimedCounterLogging : TimedCounter
- (id)initWithDescription:(NSString *)description timer:(Timer *)timer;

- (id)initWithDescription:(NSString *)description frequencySeconds:(CFAbsoluteTime)frequencySeconds;

- (id)initWithDescription:(NSString *)description;

- (bool)incrementBy:(uint)increment;
@end