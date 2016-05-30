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
    dispatch_sync_main(^{
        [UIView animateWithDuration:duration animations:^{
            [label setAlpha:1.0f];
        }                completion:block];
    });
}

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration {
    dispatch_sync_main(^{
        [UIView animateWithDuration:duration animations:^{
            [label setAlpha:0.0f];
        }                completion:block];
    });
}
@end