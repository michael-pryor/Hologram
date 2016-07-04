//
// Created by Michael Pryor on 06/12/2015.
//

#import <Foundation/Foundation.h>

@interface CustomNavigationController : UINavigationController
// Keep it alive forever, so that scroll view stays in place.
@property(nonatomic,strong) UIViewController *socialLoginViewController;
@end