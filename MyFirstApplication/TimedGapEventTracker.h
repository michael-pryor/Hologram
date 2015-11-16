//
// Created by Michael Pryor on 16/11/2015.
//

#import <Foundation/Foundation.h>


@interface TimedGapEventTracker : NSObject
- (id)initWithResetFrequency:(CFAbsoluteTime)resetFrequency;

- (uint)increment;
@end