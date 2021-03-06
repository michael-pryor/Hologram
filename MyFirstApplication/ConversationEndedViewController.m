//
//  ConversationEndedViewController.m
//  Hologram
//
//  Created by Michael Pryor on 19/06/2016.
//
//

#import "ConversationEndedViewController.h"
#import "Signal.h"

#define DEFAULT_CONVERSATION_RATING S_GOOD

@implementation ConversationEndedViewController {
    id <ConversationRatingConsumer> _conversationRatingConsumer;
    __weak IBOutlet UIButton *_goodRatingButton;
    __weak IBOutlet UIButton *_blockButton;

    NSArray *_ratingButtons;
    Signal *_ratingsCompleted;

    ConversationRating _conversationRating;
    Signal *_isFirstPress;
}

- (void)viewDidLoad {
    _ratingButtons = @[_goodRatingButton, _blockButton];
    _ratingsCompleted = [[Signal alloc] initWithFlag:false];
    _isFirstPress = [[Signal alloc] initWithFlag:false];
    [self reset];
}

- (void)viewDidLoad:(BOOL)animated {
    [self reset];
}

- (void)reset {
    [_isFirstPress clear];
    [_ratingsCompleted clear];
    for (UIButton *button in _ratingButtons) {
        [button setAlpha:1.0];
    }
    _conversationRating = DEFAULT_CONVERSATION_RATING;
}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer {
    _conversationRatingConsumer = consumer;
}

- (bool)onRatingsCompleted {
    if (![_ratingsCompleted signalAll]) {
        return false;
    }
    [_conversationRatingConsumer onConversationRating:_conversationRating];
    return true;
}

- (void)onRatingButtonPress:(id)sender rating:(ConversationRating)rating {
    bool isFirstPress = [_isFirstPress signalAll];
    if (_conversationRating == rating && (!isFirstPress || _conversationRating != DEFAULT_CONVERSATION_RATING)) {
        [self onRatingsCompleted];
        return;
    }

    _conversationRating = rating;

    for (UIButton *button in _ratingButtons) {
        if (button == sender || sender == nil) {
            [button setAlpha:1.0];
            continue;
        }

        [button setAlpha:0.5];
    }
}

- (IBAction)onGoodRatingButtonPress:(id)sender {
    [self onRatingButtonPress:sender rating:S_GOOD];
}

- (IBAction)onBlockButtonPress:(id)sender {
    [self onRatingButtonPress:sender rating:S_BLOCK];
}
@end
