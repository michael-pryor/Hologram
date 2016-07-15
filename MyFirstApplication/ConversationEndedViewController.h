//
//  ConversationEndedViewController.h
//  Hologram
//
//  Created by Michael Pryor on 19/06/2016.
//
//

#import <Foundation/Foundation.h>

// Note: these integer values map to the server, must be the same as they
// are sent and received over the network.
typedef enum {
    S_BLOCK = 2,
    S_GOOD = 3
} ConversationRating;

@protocol ConversationRatingConsumer
- (void)onConversationRating:(ConversationRating)conversationRating;
@end

@interface ConversationEndedViewController : UIViewController
- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>) consumer;

- (bool)onRatingsCompleted;

- (void)reset;
@end
