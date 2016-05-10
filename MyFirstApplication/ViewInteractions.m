//
// Created by Michael Pryor on 31/01/2016.
//

#import "ViewInteractions.h"
#import "Threading.h"


@implementation ViewInteractions {

}
+ (void)fadeInOutLabel:(UIView *)label completion:(void (^)(BOOL))block {
    dispatch_sync_main(^{
        [UIView animateWithDuration:1.0f animations:^{
            [label setAlpha:1.0f];
        }                completion:^(BOOL finished) {
            if (finished) {
                [UIView animateWithDuration:2.0f animations:^{
                    [label setAlpha:0.0f];
                }                completion:block];
            }
        }];
    });
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