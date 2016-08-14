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
#import "SingleViewCollection.h"

@protocol MediaOperator;

@interface AlertViewController : UIViewController <FBAdViewDelegate, NewImageDelegate, ConversationRatingConsumer, MatchingAnswerDelegate, CallingCardDataProvider, ViewChangeNotifier>
- (void)setGenericInformationText:(NSString *)shortText skipButtonEnabled:(bool)enabled;

- (Boolean)hideIfVisibleAndReady;

- (void)hideNow;

- (NSString *)getScreenName;

- (void)enableAdverts;

- (void)setConversationEndedViewVisible:(bool)visible showQuickly:(bool)showQuickly;

- (bool)isWaitingForMatchToJoin;

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate mediaOperator:(id <MediaOperator>)videoOperator;

- (void)setRatingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeoutSeconds:(uint)seconds;

- (void)signalMovingToFacebookController;

- (bool)shouldVideoBeOn;

- (void)reset;
@end
