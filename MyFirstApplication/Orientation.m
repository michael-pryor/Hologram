//
// Created by Michael Pryor on 29/12/2015.
//

#import "Orientation.h"


@implementation Orientation {

}

+ (UIInterfaceOrientation)getDeviceOrientation {
    return [[UIApplication sharedApplication] statusBarOrientation];
}

+ (NSString *)parseToTransitionFromGesture:(UISwipeGestureRecognizerDirection)direction {
    switch (direction) {
        case (UISwipeGestureRecognizerDirectionRight):
            return kCATransitionFromRight;

        case (UISwipeGestureRecognizerDirectionLeft):
            return kCATransitionFromLeft;

        case (UISwipeGestureRecognizerDirectionUp):
            return kCATransitionFromTop;

        case (UISwipeGestureRecognizerDirectionDown):
            return kCATransitionFromBottom;

        default:
            NSLog(@"Invalid gesture when parsing to transition");
            return nil;
    }
}

+ (UISwipeGestureRecognizerDirection)normalizeGestureWithRealDirection:(UISwipeGestureRecognizerDirection)direction {
    UIInterfaceOrientation deviceOrientation = [Orientation getDeviceOrientation];

    switch (direction) {
        case UISwipeGestureRecognizerDirectionRight: {
            switch (deviceOrientation) {
                case UIInterfaceOrientationPortrait:
                case UIInterfaceOrientationUnknown:
                    return UISwipeGestureRecognizerDirectionRight;

                case UIInterfaceOrientationPortraitUpsideDown:
                    return UISwipeGestureRecognizerDirectionLeft;

                case UIInterfaceOrientationLandscapeLeft:
                    return UISwipeGestureRecognizerDirectionUp;

                case UIInterfaceOrientationLandscapeRight:
                    return UISwipeGestureRecognizerDirectionDown;

                default:
                    NSLog(@"Invalid device orientation");
                    break;
            }
            break;
        }

        case UISwipeGestureRecognizerDirectionLeft: {
            switch (deviceOrientation) {
                case UIInterfaceOrientationPortrait:
                case UIInterfaceOrientationUnknown:
                    return UISwipeGestureRecognizerDirectionLeft;

                case UIInterfaceOrientationPortraitUpsideDown:
                    return UISwipeGestureRecognizerDirectionRight;

                case UIInterfaceOrientationLandscapeLeft:
                    return UISwipeGestureRecognizerDirectionDown;

                case UIInterfaceOrientationLandscapeRight:
                    return UISwipeGestureRecognizerDirectionUp;

                default:
                    NSLog(@"Invalid device orientation");
                    break;
            }
            break;
        }

        case UISwipeGestureRecognizerDirectionUp: {
            switch (deviceOrientation) {
                case UIInterfaceOrientationPortrait:
                case UIInterfaceOrientationUnknown:
                    return UISwipeGestureRecognizerDirectionUp;

                case UIInterfaceOrientationPortraitUpsideDown:
                    return UISwipeGestureRecognizerDirectionDown;

                case UIInterfaceOrientationLandscapeLeft:
                    return UISwipeGestureRecognizerDirectionLeft;

                case UIInterfaceOrientationLandscapeRight:
                    return UISwipeGestureRecognizerDirectionRight;

                default:
                    NSLog(@"Invalid device orientation");
                    break;
            }
            break;
        }

        case UISwipeGestureRecognizerDirectionDown: {
            switch (deviceOrientation) {
                case UIInterfaceOrientationPortrait:
                case UIInterfaceOrientationUnknown:
                    return UISwipeGestureRecognizerDirectionDown;

                case UIInterfaceOrientationPortraitUpsideDown:
                    return UISwipeGestureRecognizerDirectionUp;

                case UIInterfaceOrientationLandscapeLeft:
                    return UISwipeGestureRecognizerDirectionRight;

                case UIInterfaceOrientationLandscapeRight:
                    return UISwipeGestureRecognizerDirectionLeft;

                default:
                    NSLog(@"Invalid device orientation");
                    break;
            }
            break;
        }
    }
}
@end