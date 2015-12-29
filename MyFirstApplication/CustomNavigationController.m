//
// Created by Michael Pryor on 06/12/2015.
//

#import "CustomNavigationController.h"
#import "Orientation.h"

@implementation CustomNavigationController {

}

- (NSString *)getTransitionSubType:(bool)push {
    if (push) {
        return kCATransitionFromLeft;
    } else {
        return kCATransitionFromRight;
    }
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    UIView *theWindow = self.view;
    if (animated) {
        CATransition *animation = [CATransition animation];
        [animation setDuration:0.35f];
        [animation setType:kCATransitionPush];
        [animation setSubtype:[self getTransitionSubType:true]];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [[theWindow layer] addAnimation:animation forKey:@""];
    }

    //make sure we pass the super "animated:NO" or we will get both our
    //animation and the super's animation
    [super pushViewController:viewController animated:NO];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    UIView *theWindow = self.view;
    if (animated) {
        CATransition *animation = [CATransition animation];
        [animation setDuration:0.35f];
        [animation setType:kCATransitionPush];
        [animation setSubtype:[self getTransitionSubType:false]];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [[theWindow layer] addAnimation:animation forKey:@""];
    }
    return [super popViewControllerAnimated:NO];
}
@end