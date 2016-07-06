//
// Created by Michael Pryor on 06/07/2016.
//

#import <Foundation/Foundation.h>

@protocol MatchingAnswerDelegate
- (void) onMatchAcceptAnswer;

- (void) onMatchRejectAnswer;
@end

@interface MatchingViewController : UIViewController
- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText;

- (void)setMatchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate;
@end