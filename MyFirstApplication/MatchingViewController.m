//
// Created by Michael Pryor on 06/07/2016.
//

#import <CircleProgressBar/CircleProgressBar.h>
#import "MatchingViewController.h"
#import "Threading.h"
#import "Timer.h"
#import "CircleCountdownTimer.h"
#import "ViewInteractions.h"


@implementation MatchingViewController {
    id <MatchingAnswerDelegate> _matchingAnswerDelegate;
    CallingCardViewController *_callingCardViewController;
    __weak IBOutlet CircleProgressBar *_matchingCountdown;
    CircleCountdownTimer *_matchingCountdownTimer;
    
    
    __weak IBOutlet UIView *_skipButton;
    __weak IBOutlet UIView *_acceptButton;
    __weak IBOutlet UIButton *_backToSocialButton;
    __weak IBOutlet UIView *_blockButton;

    NSArray *_buttons;
}

- (Timer *)cloneTimer {
    return [_matchingCountdownTimer cloneTimer];
}

- (void)viewDidLoad {
    _buttons = @[_skipButton, _acceptButton, _backToSocialButton, _blockButton];
    _matchingCountdownTimer = [[CircleCountdownTimer alloc] initWithCircleProgressBar:_matchingCountdown matchingAnswerDelegate:_matchingAnswerDelegate];
}

- (void)reset {
    for (UIView *button in _buttons) {
        [button setAlpha:ALPHA_BUTTON_IMAGE_READY];
    }

    [_matchingCountdownTimer restart];
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

- (IBAction)onButtonRejectTap:(id)sender {
    if ([_matchingAnswerDelegate onMatchRejectAnswer]) {
        [self onDoneWithView:_skipButton];
    }
}

- (IBAction)onButtonAcceptPressed:(id)sender {
    [self onDoneWithView:_acceptButton];
    [_matchingAnswerDelegate onMatchAcceptAnswer];
}

- (void)onButtonPressedUpdateView:(UIView*)view {
    dispatch_sync_main(^{
        [view setAlpha:ALPHA_BUTTON_PRESSED];
    });
}

- (void)onDoneWithView:(UIView*)view {
    [_matchingCountdownTimer stopUpdating];
    [self onButtonPressedUpdateView: view];
}

- (IBAction)onSocialBackButtonPressed:(id)sender {
    [self onDoneWithView:_backToSocialButton];
    [_matchingAnswerDelegate onBackToSocialRequest];
}

- (void)setMatchingDecisionTimeoutSeconds:(uint)seconds {
    [_matchingCountdownTimer loadTimer:[[Timer alloc] initWithFrequencySeconds:seconds firingInitially:false] onlyIfNew:true];
}

- (IBAction)onBlockButtonPressed:(id)sender {
    [self onDoneWithView:_blockButton];
    [_matchingAnswerDelegate onMatchBlocked];
}
@end