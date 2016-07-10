//
// Created by Michael Pryor on 10/07/2016.
//

#import "ViewTransitions.h"
#import "AlertViewController.h"
#import "MatchingViewController.h"


@implementation ViewTransitions
+ (UIViewController *)initializeViewControllerFromParent:(UIViewController *)parent name:(NSString *)viewControllerName {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    UIViewController *subViewController = [storyboard instantiateViewControllerWithIdentifier:viewControllerName];
    subViewController.view.frame = parent.view.bounds;
    return subViewController;
}

+ (void)loadViewControllerIntoParent:(UIViewController *)parent child:(UIViewController *)child {
    [parent addChildViewController:child];
    [parent.view addSubview:child.view];
}

+ (void)presentViewController:(UIViewController *)parent child:(UIViewController *)child {
    [child didMoveToParentViewController:parent];
}

+ (UIViewController*)initializeAndLoadViewControllerIntoParent:(UIViewController *)parent name:(NSString *)viewControllerName {
    UIViewController * child = [self initializeViewControllerFromParent:parent name:viewControllerName];
    [self loadViewControllerIntoParent:parent child:child];
    return child;
}

+ (void)loadAndPresentViewController:(UIViewController *)parent child:(UIViewController *)child {
    [self loadViewControllerIntoParent:parent child:child];
    [self presentViewController:parent child:child];
}

+ (void)hideChildViewController:(UIViewController*)child {
    [child willMoveToParentViewController:nil];
    [child removeFromParentViewController];
    [child.view removeFromSuperview];
}
@end