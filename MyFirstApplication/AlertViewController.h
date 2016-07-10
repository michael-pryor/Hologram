//
//  AlertViewController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/09/2015.
//
//

@import iAd;

#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>
#import <FBAudienceNetwork/FBAudienceNetwork.h>
#import "VideoOutputController.h"
#import "ConversationEndedViewController.h"
#import "MatchingViewController.h"

@protocol MediaOperator;

@interface AlertViewController : UIViewController <FBAdViewDelegate, NewImageDelegate, ConversationRatingConsumer, MatchingAnswerDelegate, CallingCardDataProvider>
- (void)setGenericInformationText:(NSString *)shortText;

- (Boolean)hideIfVisibleAndReady;

- (void)hideNow;

- (NSString *)getScreenName;

- (void)enableAdverts;

- (void)setConversationEndedViewVisible:(bool)visible instantly:(bool)instant;

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate mediaOperator:(id <MediaOperator>)videoOperator ratingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeoutSeconds:(uint)seconds;

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance;

- (void)signalMovingToFacebookController;

- (bool)shouldVideoBeOn;
@end
