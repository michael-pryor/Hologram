//
//  ConversationEndedViewController.h
//  Hologram
//
//  Created by Michael Pryor on 19/06/2016.
//
//

#import <Foundation/Foundation.h>

typedef enum {
    S_BAD,
    S_GOOD,
    S_BLOCK,
    S_OKAY
} ConversationRating;

@protocol ConversationRatingConsumer
- (void)onConversationRating:(ConversationRating)conversationRating;
@end

@interface ConversationEndedViewController : UIViewController

@end
