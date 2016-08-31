//
// Created by Michael Pryor on 31/01/2016.
//

#import "ViewInteractions.h"
#import "Threading.h"


@implementation ViewInteractions {

}
+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block {
    [ViewInteractions fadeInOut:entity completion:block options:UIViewAnimationOptionTransitionNone | UIViewAnimationOptionCurveEaseInOut];
}

+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block options:(UIViewAnimationOptions)options fadeInDuration:(float)durationIn fadeOutDuration:(float)durationOut fadeOutDelay:(float)delay {
    dispatch_sync_main(^{
        [UIView animateWithDuration:durationIn delay:0 options:options animations:^{
            [entity setAlpha:1.0f];
        }                completion:^(BOOL finished) {
            if (finished) {
                [UIView animateWithDuration:durationOut delay:delay options:options animations:^{
                    [entity setAlpha:0.0f];
                }                completion:block];
            }
        }];
    });
}

+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block options:(UIViewAnimationOptions)options {
    [ViewInteractions fadeInOut:entity completion:block options:options fadeInDuration:1.0f fadeOutDuration:2.0f fadeOutDelay:0];
}

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration {
    [self fadeIn:label completion:block duration:duration toAlpha:1.0f];
}


+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha options:(UIViewAnimationOptions)options {
    dispatch_sync_main(^{
        [UIView animateWithDuration:duration delay:0 options:options animations:^{
            [label setAlpha:alpha];
        }                completion:block];
    });
}

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha {
    [self fadeIn:label completion:block duration:duration toAlpha:alpha options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone];
}

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration {
    [self fadeOut:label completion:block duration:duration toAlpha:0];
}

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha {
    [self fadeOut:label completion:block duration:duration toAlpha:alpha options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone];
}

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha options:(UIViewAnimationOptions)options {
    dispatch_sync_main(^{
        [UIView animateWithDuration:duration delay:0 options:options animations:^{
            [label setAlpha:alpha];
        }                completion:block];
    });
}

+ (void)fadeOut:(UIView *)viewA thenIn:(UIView *)viewB duration:(float)duration {
    [ViewInteractions fadeOut:viewA completion:^(BOOL finished) {
        if (!finished) {
            [viewA setAlpha:0];
        }

        [ViewInteractions fadeIn:viewB completion:^(BOOL completed) {
            if (!completed) {
                [viewB setAlpha:1];
            }
        }               duration:duration];
    }                duration:duration];
}
@end