//
// Created by Michael Pryor on 06/12/2015.
//

#import "CustomNavigationController.h"

@implementation CustomNavigationController {

}

- (NSString *)getTransitionSubType:(bool)push {
    if (push) {
        return kCATransitionFromLeft;
    } else {
        return kCATransitionFromRight;
    }
}

- (void)prepareAnimationForView:(UIView *)theWindow pushing:(bool)push {
    CATransition *animation = [CATransition animation];
    [animation setDuration:0.35f];
    [animation setType:kCATransitionPush];
    [animation setSubtype:[self getTransitionSubType:push]];
    [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    [[theWindow layer] addAnimation:animation forKey:@""];
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (animated) {
        NSString *identifier = [viewController restorationIdentifier];
        if ([@"BannedViewController" isEqualToString:identifier] || [@"FacebookSharedViewController" isEqualToString:identifier] ) {
            [self prepareAnimationForView:self.view pushing:false];
        } else {
            [self prepareAnimationForView:self.view pushing:true];
        }

        // This prevents cleanup.
        if ([@"FacebookView" isEqualToString:identifier]) {
            if (_socialLoginViewController == nil) {
                _socialLoginViewController = viewController;
            } else {
                viewController = _socialLoginViewController;
            }
        }
    }

    //make sure we pass the super "animated:NO" or we will get both our
    //animation and the super's animation
    [super pushViewController:viewController animated:NO];
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated {
    if (animated) {
        [self prepareAnimationForView:self.view pushing:false];
    }

    return [super popToRootViewControllerAnimated:NO];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    if (animated) {
        [self prepareAnimationForView:self.view pushing:false];
    }
    return [super popViewControllerAnimated:NO];
}
@end