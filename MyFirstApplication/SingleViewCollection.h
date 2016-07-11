//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@protocol ViewChangeNotifier
- (void)onStartedFadingIn:(UIView*)view duration:(float)duration;

- (void)onStartedFadingOut:(UIView*)view duration:(float)duration;

- (void)onFinishedFadingIn:(UIView*)view duration:(float)duration;

- (void)onFinishedFadingOut:(UIView*)view duration:(float)duration;
@end

@interface SingleViewCollection : NSObject
- (id)initWithDuration:(float)duration viewChangeNotifier:(id<ViewChangeNotifier>)viewChangeNotifier;

- (void)displayView:(UIView *)view;

- (UIView*)getCurrentlyDisplayedView;

- (bool)isViewDisplayedWideSearch:(UIView *)view;

- (void)displayView:(UIView *)view ifNoChangeForMilliseconds:(uint)milliseconds;
@end