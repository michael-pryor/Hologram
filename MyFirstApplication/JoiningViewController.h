//
// Created by Michael Pryor on 10/07/2016.
//

#import <Foundation/Foundation.h>

@class Timer;
@protocol MatchingAnswerDelegate;


@interface JoiningViewController : UIViewController
- (void)consumeRemainingTimer:(Timer *)timer;

- (void)setTimeoutDelegate:(id <MatchingAnswerDelegate>)timeoutDelegate;

- (void)stop;

- (void)reset;

- (void)updateColours:(bool)isClientOnline;
@end