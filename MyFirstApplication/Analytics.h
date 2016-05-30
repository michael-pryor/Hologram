//
// Created by Michael Pryor on 26/05/2016.
//

#import <Foundation/Foundation.h>

#import "Timer.h"

@interface DeferredEvent : NSObject
- (void)increment;

- (void)start;

- (void)pause;
@end

@interface Analytics : NSObject
+ (Analytics *)getInstance;

- (void)pushScreenChange:(NSString *)newScreenName;

- (void)pushTimingSeconds:(NSTimeInterval)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name;

- (void)pushTimingSeconds:(NSTimeInterval)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name label:(NSString *)label;

- (void)pushTimer:(Timer *)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name label:(NSString *)label;

- (void)pushTimer:(Timer *)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name;

- (void)pushEventWithCategory:(NSString *)category action:(NSString *)action label:(NSString *)label value:(NSNumber *)value;

- (void)pushEventWithCategory:(NSString *)category action:(NSString *)action label:(NSString *)label;

- (void)pushEventWithCategory:(NSString *)category action:(NSString *)action;

- (DeferredEvent *)deferEventWithFrequencySeconds:(NSTimeInterval)frequency category:(NSString *)category action:(NSString *)action label:(NSString *)label;

- (DeferredEvent *)deferEventWithFrequencySeconds:(NSTimeInterval)frequency category:(NSString *)category action:(NSString *)action;
@end