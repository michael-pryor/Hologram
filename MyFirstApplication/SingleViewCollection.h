//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@protocol ViewChangeNotifier
@optional
- (void)onStartedDisplayingView:(UIView*)view;

- (void)onFinishedDisplayingView:(UIView*)view;
@end

@interface SingleViewCollection : NSObject
- (id)initWithDuration:(float)duration viewChangeNotifier:(id<ViewChangeNotifier>)viewChangeNotifier;

- (void)displayView:(UIView *)view;

- (UIView*)getCurrentlyDisplayedView;

- (bool)isViewDisplayedWideSearch:(UIView *)view;
@end