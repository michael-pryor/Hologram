//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>


@interface ViewTransitions : NSObject
+ (UIViewController *)initializeViewControllerFromParent:(UIViewController *)parent name:(NSString *)viewControllerName;

+ (void)loadViewControllerIntoParent:(UIViewController *)parent child:(UIViewController *)child;

+ (void)presentViewController:(UIViewController *)parent child:(UIViewController *)child;

+ (void)loadAndPresentViewController:(UIViewController *)parent child:(UIViewController *)child;

+ (void)hideChildViewController:(UIViewController*)child;

+ (UIViewController*)initializeAndLoadViewControllerIntoParent:(UIViewController *)parent name:(NSString *)viewControllerName;
@end