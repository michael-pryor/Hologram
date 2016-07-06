//
// Created by Michael Pryor on 04/07/2016.
//

#import "HelpViewController.h"
#import "ConnectionViewController.h"
#import "Threading.h"
#import "CallingCardViewController.h"


@implementation HelpViewController {
    __weak IBOutlet UIProgressView *_karmaProgressBar;
    int _karma;
    int _karmaMax;

    ConversationEndedViewController *_conversationEndedViewController;
}

- (void)viewDidLoad {
    _karmaMax = 5;
    _karma = _karmaMax;

    // Set things up, colour the bar properly.
    [self onConversationRating:S_OKAY];
}

- (IBAction)onDoneButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSString *segueName = segue.identifier;
    if ([segueName isEqualToString:@"KarmaRater"]) {
        _conversationEndedViewController = [segue destinationViewController];
        [_conversationEndedViewController setConversationRatingConsumer:self];
    } else if ([segueName isEqualToString:@"CallingCard"]) {
        CallingCardViewController *callingCardViewController = [segue destinationViewController];
        SocialState *socialState = [SocialState getSocialInstance];
        [callingCardViewController setName:[socialState humanFullName] text:[socialState callingCardText] profilePicture:[socialState profilePictureImage]];
    }
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    dispatch_sync_main(^{
        if (conversationRating == S_BAD || conversationRating == S_BLOCK) {
            _karma--;
        } else if (conversationRating == S_GOOD) {
            _karma++;
        }

        if (_karma > _karmaMax) {
            _karma = _karmaMax;
        }

        if (_karma < 0) {
            _karma = 0;
        }

        float ratio = ((float) _karma) / ((float) _karmaMax);
        [ConnectionViewController updateKarmaUsingProgressView:_karmaProgressBar ratio:ratio];
        [_conversationEndedViewController reset];
    });
}

@end