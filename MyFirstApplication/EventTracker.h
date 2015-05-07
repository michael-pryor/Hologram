//
//  NSObject+EventTracker.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/04/2015.
//
//

@interface EventTracker : NSObject
- (id) initWithMaxEvents:(uint)maxEvents;
- (Boolean) increment;
- (void) reset;
- (uint) getNumFailures;
@end
