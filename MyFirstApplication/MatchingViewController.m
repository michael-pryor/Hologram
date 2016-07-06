//
// Created by Michael Pryor on 06/07/2016.
//

#import "MatchingViewController.h"
#import "Threading.h"


@implementation MatchingViewController {

    __weak IBOutlet UILabel *_name;

    id <MatchingAnswerDelegate> _matchingAnswerDelegate;
}

- (void)setMatchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate {
    _matchingAnswerDelegate = matchingAnswerDelegate;
}

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText {
    dispatch_sync_main(^{
        [_name setText:name];
    });
}

- (IBAction)onButtonRejectPressed:(id)sender {
    [_matchingAnswerDelegate onMatchRejectAnswer];
}

- (IBAction)onButtonAcceptPressed:(id)sender {
    [_matchingAnswerDelegate onMatchAcceptAnswer];
}
@end