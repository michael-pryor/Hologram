//
// Created by Michael Pryor on 17/11/2015.
//

#import <Foundation/Foundation.h>

/**
 * Tracks average over last x amount of time.
 */
@interface AverageTrackerLimitedSize : NSObject
- (id)initWithMaxSize:(uint)sizeLimit;

- (void)addValue:(uint)value;

- (double)getWeightedAverage;
@end