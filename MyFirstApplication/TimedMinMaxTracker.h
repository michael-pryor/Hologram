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

- (id)initWithResetFrequencySeconds:(CFAbsoluteTime)resetFrequency;

- (void)onValue:(uint)value result:(TimedMinMaxTrackerResult *)outResult hasResult:(bool *)outHasResult;

- (TimedMinMaxTrackerResult)reset;

- (CFAbsoluteTime)getFrequencySeconds;
@end