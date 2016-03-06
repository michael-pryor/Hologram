//
// Created by Michael Pryor on 06/03/2016.
//

#import <Foundation/Foundation.h>

struct TimedMinMaxTrackerResult {
    uint min;
    uint max;
};
typedef struct TimedMinMaxTrackerResult TimedMinMaxTrackerResult;

@interface TimedMinMaxTracker : NSObject
@property(readonly) uint min;
@property(readonly) uint max;
@property(readonly) uint startingValue;

- (id)initWithResetFrequencySeconds:(CFAbsoluteTime)resetFrequency startingValue:(uint)startingValue;

- (void)onValue:(uint)value result:(TimedMinMaxTrackerResult *)outResult hasResult:(bool *)outHasResult;

- (TimedMinMaxTrackerResult)reset;

- (CFAbsoluteTime)getFrequencySeconds;
@end