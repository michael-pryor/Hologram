//
// Created by Michael Pryor on 06/12/2015.
//

#import "CustomNavigationController.h"


@implementation CustomNavigationController {

}

- (NSString*)getTransitionSubType:(bool)push {
    bool isUpright;
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    switch(orientation) {
        case UIDeviceOrientationUnknown:
        case UIDeviceOrientationPortrait:           // Device oriented vertically, home button on the bottom
        case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
        case UIDeviceOrientationFaceUp:              // Device oriented flat, face up
        case UIDeviceOrientationFaceDown:
            isUpright = true;
            break;
            
        case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
        case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
        default:
            isUpright = false;
            break;
            
    }
    
    if(isUpright) {
        if (push) {
            return kCATransitionFromLeft;
        } else {
            return kCATransitionFromRight;
        }
    } else {
        if (push) {
            return kCATransitionFromBottom;
        } else {
            return kCATransitionFromTop;
        }
    }
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated{
    UIView *theWindow = self.view ;
    if( animated ) {
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
    UIView *theWindow = self.view ;
    if( animated ) {
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