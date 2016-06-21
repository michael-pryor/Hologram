//
//  ConversationEndedViewController.m
//  Hologram
//
//  Created by Michael Pryor on 19/06/2016.
//
//

#import "ConversationEndedViewController.h"

@implementation ConversationEndedViewController {
    id <ConversationRatingConsumer> _conversationRatingConsumer;
    __weak IBOutlet UIButton *_okayRatingButton;
    __weak IBOutlet UIButton *_goodRatingButton;
    __weak IBOutlet UIButton *_badRatingButton;
    __weak IBOutlet UIButton *_blockButton;

    NSArray *_ratingButtons;
}

- (void)viewDidLoad {
    _ratingButtons = @[_okayRatingButton, _goodRatingButton, _badRatingButton, _blockButton];
}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>) consumer {
    _conversationRatingConsumer = consumer;
}

- (void)onRatingButtonPress:(id)sender {
    for (UIButton *button in _ratingButtons) {
        if (button == sender || sender == nil) {
            [button setEnabled:true];
            continue;
        }

        [button setEnabled:false];
    }
}

- (void)resetState {
    [self onRatingButtonPress:nil];
}

- (IBAction)onOkayRatingButtonPress:(id)sender {
    [self onRatingButtonPress:sender];
    [_conversationRatingConsumer onConversationRating:S_OKAY];
}

- (IBAction)onGoodRatingButtonPress:(id)sender {
    [self onRatingButtonPress:sender];
    [_conversationRatingConsumer onConversationRating:S_GOOD];
}

- (IBAction)onBadRatingButtonPress:(id)sender {
    [self onRatingButtonPress:sender];
    [_conversationRatingConsumer onConversationRating:S_BAD];
}

- (IBAction)onBlockButtonPress:(id)sender {
    [self onRatingButtonPress:sender];
    [_conversationRatingConsumer onConversationRating:S_BLOCK];
}
@end
