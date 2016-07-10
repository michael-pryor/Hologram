//
// Created by Michael Pryor on 06/07/2016.
//

#import <CircleProgressBar/CircleProgressBar.h>
#import "MatchingViewController.h"
#import "Threading.h"
#import "Timer.h"
#import "Signal.h"
#import "CircleCountdownTimer.h"


@implementation MatchingViewController {
    id <MatchingAnswerDelegate> _matchingAnswerDelegate;
    CallingCardViewController *_callingCardViewController;
    __weak IBOutlet CircleProgressBar *_matchingCountdown;
    CircleCountdownTimer *_matchingCountdownTimer;
}

- (Timer*)cloneTimer {
    return [_matchingCountdownTimer cloneTimer];
}

- (void)viewDidLoad {
    _matchingCountdownTimer = [[CircleCountdownTimer alloc] initWithCircleProgressBar:_matchingCountdown matchingAnswerDelegate:_matchingAnswerDelegate];
}

- (void)reset {
    [_matchingCountdownTimer reset];
    [_matchingCountdownTimer startUpdating];
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

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance {
    dispatch_sync_main(^{
        [_callingCardViewController setName:name profilePicture:profilePicture callingCardText:callingCardText age:age distance:distance];
        [self reset];
    });
}

- (IBAction)onButtonRejectPressed:(id)sender {
    [_matchingAnswerDelegate onMatchRejectAnswer];
}

- (IBAction)onButtonAcceptPressed:(id)sender {
    
    [_matchingAnswerDelegate onMatchAcceptAnswer];
}

- (void)setMatchingDecisionTimeoutSeconds:(uint)seconds {
    [_matchingCountdownTimer loadTimer:[[Timer alloc] initWithFrequencySeconds:seconds firingInitially:false] onlyIfNew:true];
}
- (IBAction)onBlockButtonPressed:(id)sender {
    [_matchingAnswerDelegate onMatchBlocked];
}
@end