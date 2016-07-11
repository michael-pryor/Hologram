//
// Created by Michael Pryor on 06/07/2016.
//

#import <Foundation/Foundation.h>
#import "CallingCardViewController.h"

@class Timer;

@protocol MatchingAnswerDelegate
- (void) onMatchAcceptAnswer;

- (bool) onMatchRejectAnswer;

- (void) onMatchBlocked;

- (void) onBackToSocialRequest;

- (void) onTimedOut;
@end

@interface MatchingViewController : UIViewController<CallingCardDataProvider>
- (void)setMatchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate;

- (void)setMatchingDecisionTimeoutSeconds:(uint)seconds;

- (void)reset;

- (Timer*)cloneTimer;
@end