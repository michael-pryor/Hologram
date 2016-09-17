//
// Created by Michael Pryor on 16/09/2016.
//

#import "TextualViewController.h"
#import "CircleProgressBar.h"
#import "Timer.h"


@implementation TextualViewController {
    __weak IBOutlet CircleProgressBar *_progressCircleView;
    CircleCountdownTimer *_progressCircleViewCountdown;
}

- (void)viewDidLoad {
    _progressCircleViewCountdown = [[CircleCountdownTimer alloc] initWithCircleProgressBar:_progressCircleView matchingAnswerDelegate:self];
    [_progressCircleViewCountdown enableInfiniteMode:0.25f];
    [_progressCircleViewCountdown loadTimer:[[Timer alloc] initWithFrequencySeconds:5 firingInitially:false]];
}

- (void)onTimedOut {

}

- (void)stop {
    [_progressCircleViewCountdown stopUpdating];
}

- (void)reset {
    [_progressCircleViewCountdown restart];
}

@end