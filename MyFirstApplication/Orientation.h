//
// Created by Michael Pryor on 29/12/2015.
//

#import <Foundation/Foundation.h>


@interface Orientation : NSObject
+ (UIInterfaceOrientation)getDeviceOrientation;

+ (UISwipeGestureRecognizerDirection)normalizeGestureWithRealDirection:(UISwipeGestureRecognizerDirection)direction;

+ (NSString *)parseToTransitionFromGesture:(UISwipeGestureRecognizerDirection)direction;
@end