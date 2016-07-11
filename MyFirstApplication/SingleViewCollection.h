//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@protocol ViewChangeNotifier
@optional
- (void)onStartedDisplayingView:(UIView*)view;

- (void)onFinishedDisplayingView:(UIView*)view;

- (void)onStartedFadingIn:(UIView*)view;

- (void)onStartedFadingOut:(UIView*)view;

- (void)onFinishedFadingIn:(UIView*)view;

- (void)onFinishedFadingOut:(UIView*)view;

- (void)onGenericAcivity:(UIView *)view activity:(NSString*)activity;
@end

@interface SingleViewCollection : NSObject
- (id)initWithDuration:(float)duration viewChangeNotifier:(id<ViewChangeNotifier>)viewChangeNotifier;

- (void)displayView:(UIView *)view;

- (UIView*)getCurrentlyDisplayedView;

- (bool)isViewDisplayedWideSearch:(UIView *)view;
@end