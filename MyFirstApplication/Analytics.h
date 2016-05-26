//
// Created by Michael Pryor on 26/05/2016.
//

#import <Foundation/Foundation.h>

#import "Timer.h"


@interface Analytics : NSObject
+ (Analytics *)getInstance;

- (void)pushScreenChange:(NSString *)newScreenName;

- (void)pushTimingSeconds:(NSTimeInterval)timeSinceLastStateChangeSeconds toAnalyticsWithCategory:(NSString *)category name:(NSString *)name;

- (void)pushTimingSeconds:(NSTimeInterval)timeSinceLastStateChangeSeconds toAnalyticsWithCategory:(NSString *)category name:(NSString *)name label:(NSString *)label;

- (void)pushTimer:(Timer *)timeSinceLastStateChangeSeconds toAnalyticsWithCategory:(NSString *)category name:(NSString *)name label:(NSString *)label;

- (void)pushTimer:(Timer *)timeSinceLastStateChangeSeconds toAnalyticsWithCategory:(NSString *)category name:(NSString *)name;
@end