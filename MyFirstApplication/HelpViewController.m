//
// Created by Michael Pryor on 04/07/2016.
//

#import "HelpViewController.h"
#import "ConnectionViewController.h"
#import "Threading.h"
#import "CallingCardViewController.h"
#import "ViewStringFormatting.h"


@implementation HelpViewController {
    __weak IBOutlet UIProgressView *_karmaProgressBar;
    int _karma;
    int _karmaMax;

    ConversationEndedViewController *_conversationEndedViewController;
    
    __weak IBOutlet UIView *_callingCardView;
    __weak IBOutlet UIView *_callingCardContainerView;
}

- (void)viewDidLoad {
    self.screenName = @"Help";

    _karmaMax = 10;
    _karma = _karmaMax;

    // Set things up, colour the bar properly.
    [self onConversationRating:S_GOOD];
}



- (IBAction)onDoneButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (IBAction)onVideoTestButtonPressed:(id)sender {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    UIViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"VideoLoopbackViewController"];
    [self presentViewController:viewController animated:YES completion:nil];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSString *segueName = segue.identifier;
    if ([segueName isEqualToString:@"KarmaRater"]) {
        _conversationEndedViewController = [segue destinationViewController];
        [_conversationEndedViewController setConversationRatingConsumer:self];
    } else if ([segueName isEqualToString:@"CallingCard"]) {
        CallingCardViewController *callingCardViewController = [segue destinationViewController];
        callingCardViewController.view.backgroundColor = _callingCardContainerView.backgroundColor;
        SocialState *socialState = [SocialState getSocialInstance];
        [callingCardViewController setName:[socialState humanShortName] profilePicture:[socialState profilePictureImage] callingCardText:[socialState callingCardText] age:[socialState age] distance:0 karma:5 maxKarma:5 isReconnectingClient:false];
    }
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    dispatch_sync_main(^{
        if (conversationRating == S_BLOCK) {
            _karma-=2;
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
        [ViewStringFormatting updateKarmaUsingProgressView:_karmaProgressBar ratio:ratio];
        [_conversationEndedViewController reset];
    });
}

@end