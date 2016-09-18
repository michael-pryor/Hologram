//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@class CircleProgressBar;
@protocol MatchingAnswerDelegate;
@class Timer;

@protocol TimeoutDelegate
@optional
- (void)onTimedOut;
@end

@interface CircleCountdownTimer : NSObject
- (id)initWithCircleProgressBar:(CircleProgressBar *)circleProgressBar matchingAnswerDelegate:(id <TimeoutDelegate>)matchingAnswerDelegate;

- (void)reset;

- (void)loadTimer:(Timer *)timer;

- (void)loadTimer:(Timer *)timer onlyIfNew:(bool)mustBeNew;

- (void)startUpdating;

- (Timer*)cloneTimer;

- (void)stopUpdating;

- (void)enableInfiniteMode;
@end