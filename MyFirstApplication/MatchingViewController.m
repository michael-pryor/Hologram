//
// Created by Michael Pryor on 06/07/2016.
//

#import "MatchingViewController.h"
#import "Threading.h"
#import "CallingCardViewController.h"
#import "SocialState.h"


@implementation MatchingViewController {

    __weak IBOutlet UILabel *_name;

    id <MatchingAnswerDelegate> _matchingAnswerDelegate;
    CallingCardViewController *_callingCardViewController;
}

- (void)setMatchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate {
    _matchingAnswerDelegate = matchingAnswerDelegate;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSString *segueName = segue.identifier;
    if ([segueName isEqualToString:@"CallingCard"]) {
        _callingCardViewController = [segue destinationViewController];
    }
}

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance{
    dispatch_sync_main(^{
        [_callingCardViewController setName:name profilePicture:profilePicture callingCardText:callingCardText age:age distance:distance];
    });
}

- (IBAction)onButtonRejectPressed:(id)sender {
    [_matchingAnswerDelegate onMatchRejectAnswer];
}

- (IBAction)onButtonAcceptPressed:(id)sender {
    [_matchingAnswerDelegate onMatchAcceptAnswer];
}
@end