//
// Created by Michael Pryor on 26/05/2016.
//

#import "Analytics.h"
#import <Google/Analytics.h>
#import "Signal.h"

static Analytics *instance = nil;

@implementation DeferredEvent {
    uint _count;
    NSTimeInterval _frequencySeconds;

    NSString *_category;
    NSString *_action;
    NSString *_label;

    dispatch_queue_t _schedulingQueue;
    Analytics *_parent;

    Signal *_pausedSignal;
}
- (id)initWithSchedulingQueue:(dispatch_queue_t)queue frequencySeconds:(NSTimeInterval)frequency parent:(Analytics *)parent category:(NSString *)category action:(NSString *)action label:(NSString *)label {
    self = [super init];
    if (self) {
        _count = 0;
        _frequencySeconds = frequency;
        _category = category;
        _action = action;
        _label = label;
        _schedulingQueue = queue;
        _parent = parent;
        _pausedSignal = [[Signal alloc] initWithFlag:false];
    }
    return self;
}

- (void)increment {
    @synchronized (self) {
        _count++;
    }
}

- (void)pause {
    [_pausedSignal signalAll];
}

- (void)start {
    [_pausedSignal clear];
    [self _start];
}

- (void)_start {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (_frequencySeconds * NSEC_PER_SEC)), _schedulingQueue, ^{
        @synchronized (self) {
            if (_count > 0) {
                NSLog(@"Deferred event being published after %.1f seconds with category [%@], action [%@], label [%@] and count [%d]", _frequencySeconds, _category, _action, _label, _count);
                [_parent pushEventWithCategory:_category action:_action label:_label value:@(_count)];
                _count = 0;
            }

            if (![_pausedSignal clear]) {
                [self _start];
            }
        }
    });
}
@end

@implementation Analytics {
    dispatch_queue_t _schedulingQueue;
}

- (id)init {
    self = [super init];
    if (self) {
        _schedulingQueue = dispatch_queue_create("AnalyticsDeferred", NULL);
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

- (DeferredEvent *)deferEventWithFrequencySeconds:(NSTimeInterval)frequency category:(NSString *)category action:(NSString *)action label:(NSString *)label {
    return [[DeferredEvent alloc] initWithSchedulingQueue:_schedulingQueue frequencySeconds:frequency parent:self category:category action:action label:label];
}

- (DeferredEvent *)deferEventWithFrequencySeconds:(NSTimeInterval)frequency category:(NSString *)category action:(NSString *)action {
    return [self deferEventWithFrequencySeconds:frequency category:category action:action label:nil];
}
@end