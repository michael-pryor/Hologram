//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@class CircleProgressBar;
@protocol MatchingAnswerDelegate;
@class Timer;


@interface CircleCountdownTimer : NSObject
- (id)initWithCircleProgressBar:(CircleProgressBar *)circleProgressBar matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate;

- (void)restart;

- (void)loadTimer:(Timer *)timer;

- (void)loadTimer:(Timer *)timer onlyIfNew:(bool)mustBeNew;

- (void)startUpdating;

- (Timer*)cloneTimer;

- (void)stopUpdating;
@end