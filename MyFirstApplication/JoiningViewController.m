//
// Created by Michael Pryor on 10/07/2016.
//

#import "JoiningViewController.h"
#import "Timer.h"
#import "CircleProgressBar.h"
#import "Signal.h"
#import "Threading.h"
#import "CircleCountdownTimer.h"
#import "MatchingViewController.h"


@implementation JoiningViewController {
    __weak IBOutlet CircleProgressBar *_progressBar;
    CircleCountdownTimer *_countdownTimer;
    id<MatchingAnswerDelegate> _timeoutDelegate;
}
- (void)consumeRemainingTimer:(Timer*)timer {
    [_countdownTimer loadTimer:timer];
    [_countdownTimer startUpdating];
}

- (void) setTimeoutDelegate:(id<MatchingAnswerDelegate>)timeoutDelegate {
    _timeoutDelegate = timeoutDelegate;
}

- (void)viewDidLoad {
    _countdownTimer = [[CircleCountdownTimer alloc] initWithCircleProgressBar:_progressBar matchingAnswerDelegate:_timeoutDelegate];
}

- (void)reset {
    [_countdownTimer restart];
}

- (void)stop {
    [_countdownTimer stopUpdating];
}
@end