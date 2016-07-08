//
// Created by Michael Pryor on 06/07/2016.
//

#import <CircleProgressBar/CircleProgressBar.h>
#import "MatchingViewController.h"
#import "Threading.h"
#import "Timer.h"
#import "Signal.h"


@implementation MatchingViewController {

    __weak IBOutlet UILabel *_name;

    id <MatchingAnswerDelegate> _matchingAnswerDelegate;
    CallingCardViewController *_callingCardViewController;
    __weak IBOutlet CircleProgressBar *_matchingCountdown;

    Timer *_timeoutTimer;
    Signal *_updatingMatchingCountdown;
}

- (void)viewDidLoad {
    _updatingMatchingCountdown = [[Signal alloc] initWithFlag:false];
    [_matchingCountdown setHintTextGenerationBlock:^NSString *(CGFloat progress) {
        int secondsLeft = (int) [_timeoutTimer getSecondsUntilNextTick];
        return [NSString stringWithFormat:@"%d", secondsLeft];
    }];
}

- (void)reset {
    if (_timeoutTimer != nil) {
        [_matchingCountdown setProgress:0 animated:false];
        [_timeoutTimer reset];
        [self updateProgress];
    }
}

- (void)updateProgress {
    dispatch_sync_main(^{
    if ([_updatingMatchingCountdown signalAll]) {
        [self doUpdateProgress];
    }
        });
}

- (void)doUpdateProgress {
    dispatch_sync_main(^{
        float ratioProgress = [_timeoutTimer getRatioProgressThroughTick];
        [_matchingCountdown setProgress:ratioProgress animated:true];
        if (ratioProgress >= 1.0) {
            [_updatingMatchingCountdown clear];
            [_matchingAnswerDelegate onTimedOut];
            return;
        }

        dispatch_async_main(^{
            [self doUpdateProgress];
        }, 100);
    });
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
    if (_timeoutTimer == nil) {
        _timeoutTimer = [[Timer alloc] initWithFrequencySeconds:seconds firingInitially:false];
    } else {
        [_timeoutTimer setSecondsFrequency:seconds];
    }
}
@end