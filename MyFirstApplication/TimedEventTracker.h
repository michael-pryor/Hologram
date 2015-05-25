//
//  TimedEventTracker.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import <Foundation/Foundation.h>

@interface TimedEventTracker : NSObject
- (id)initWithMaxEvents:(uint)maxEvents timePeriod:(CFAbsoluteTime)defaultOutputFrequency;
- (Boolean)increment;
- (void)reset;
- (void)setTimePeriod:(CFAbsoluteTime)outputFrequency;
- (void)resetTimePeriod;
@end
