//
// Created by Michael Pryor on 06/07/2016.
//

#import <Foundation/Foundation.h>
#import "CallingCardViewController.h"

@protocol MatchingAnswerDelegate
- (void) onMatchAcceptAnswer;

- (void) onMatchRejectAnswer;
@end

@interface MatchingViewController : UIViewController<CallingCardDataProvider>
- (void)setMatchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate;
@end