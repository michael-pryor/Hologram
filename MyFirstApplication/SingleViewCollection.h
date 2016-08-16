//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@protocol ViewChangeNotifier
- (void)onStartedFadingIn:(UIView *)view duration:(float)duration meta:(id)meta;

- (void)onStartedFadingOut:(UIView *)view duration:(float)duration alpha:(float)alpha;

- (void)onFinishedFadingIn:(UIView *)view duration:(float)duration meta:(id)meta;

- (void)onFinishedFadingOut:(UIView *)view duration:(float)duration alpha:(float)alpha;
@end

@interface SingleViewCollection : NSObject
- (id)initWithDuration:(float)duration viewChangeNotifier:(id<ViewChangeNotifier>)viewChangeNotifier;

- (void)displayView:(UIView *)view meta:(id)meta;

- (UIView*)getCurrentlyDisplayedView;

- (bool)isViewCurrent:(UIView *)view;

- (void)displayView:(UIView *)view ifNoChangeForMilliseconds:(uint)milliseconds meta:(id)meta;

- (void)registerNoFadeView:(UIView *)view;
@end