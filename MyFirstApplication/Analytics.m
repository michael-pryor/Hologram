//
// Created by Michael Pryor on 26/05/2016.
//

#import "Analytics.h"
#import <Google/Analytics.h>

static Analytics *instance = nil;

@implementation Analytics {

}

- (id)init {
    self = [super init];
    if (self) {

    }
    return self;
}

+ (Analytics *)getInstance {
    @synchronized (self) {
        if (instance == nil) {
            instance = [[Analytics alloc] init];
        }

        return instance;
    }
}

- (id)tracker {
    return [[GAI sharedInstance] defaultTracker];
}

- (void)pushScreenChange:(NSString *)newScreenName {
    // Manually notify Google analytics that we are now on this screen.
    // Have to do manually, because we overlay this view on top of ours rather than moving directly to it.
    id tracker = [self tracker];
    [tracker set:kGAIScreenName value:newScreenName];
    [tracker send:[[GAIDictionaryBuilder createScreenView] build]];
}

- (void)pushTimingSeconds:(NSTimeInterval)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name {
    [self pushTimingSeconds:timeSinceLastStateChangeSeconds withCategory:category name:name label:nil];
}

- (void)pushTimingSeconds:(NSTimeInterval)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name label:(NSString *)label {
    id tracker = [self tracker];
    [tracker send:[[GAIDictionaryBuilder createTimingWithCategory:category
                                                         interval:@((NSUInteger) (timeSinceLastStateChangeSeconds * 1000.0))
                                                             name:name
                                                            label:label] build]];
}

- (void)pushTimer:(Timer *)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name label:(NSString *)label {
    [self pushTimingSeconds:[timeSinceLastStateChangeSeconds getSecondsSinceLastTick] withCategory:category name:name label:label];
}

- (void)pushTimer:(Timer *)timeSinceLastStateChangeSeconds withCategory:(NSString *)category name:(NSString *)name {
    [self pushTimingSeconds:[timeSinceLastStateChangeSeconds getSecondsSinceLastTick] withCategory:category name:name];
}

- (void)pushEventWithCategory:(NSString *)category action:(NSString *)action label:(NSString *)label value:(NSNumber *)value {
    id tracker = [self tracker];
    [tracker send:[[GAIDictionaryBuilder createEventWithCategory:category action:action label:label value:value] build]];
}

- (void)pushEventWithCategory:(NSString *)category action:(NSString *)action label:(NSString *)label {
    [self pushEventWithCategory:category action:action label:label value:nil];
}

- (void)pushEventWithCategory:(NSString *)category action:(NSString *)action {
    [self pushEventWithCategory:category action:action label:nil value:nil];
}
@end