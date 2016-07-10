//
// Created by Michael Pryor on 10/07/2016.
//

#import "CircleCountdownTimer.h"
#import "CircleProgressBar.h"
#import "Signal.h"
#import "Timer.h"
#import "Threading.h"
#import "MatchingViewController.h"


@implementation CircleCountdownTimer {
    CircleProgressBar *_progressObject;
    Timer *_timeoutTimer;
    Signal *_updatingUi;
    id <MatchingAnswerDelegate> _timeoutDelegate;
    bool _stopped;
}

- (id)initWithCircleProgressBar:(CircleProgressBar *)circleProgressBar matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate {
    self = [super init];
    if (self) {
        _progressObject = circleProgressBar;
        _timeoutDelegate = matchingAnswerDelegate;
        _updatingUi = [[Signal alloc] initWithFlag:false];
        _timeoutTimer = nil;
        _stopped = false;
    }
    return self;
}

- (void)viewDidLoad {
    _updatingUi = [[Signal alloc] initWithFlag:false];
    [_progressObject setHintTextGenerationBlock:^NSString *(CGFloat progress) {
        int secondsLeft = (int) [_timeoutTimer getSecondsUntilNextTick];
        return [NSString stringWithFormat:@"%d", secondsLeft];
    }];
}

- (void)restart {
    dispatch_sync_main(^{
        [_progressObject setProgress:0 animated:false];
    });

    if (_timeoutTimer != nil) {
        [_timeoutTimer reset];
        [self startUpdating];
    }
}

- (void)stopUpdating {
    dispatch_sync_main(^{
        if ([_updatingUi clear]) {
            _stopped = true;
        }
    });
}

- (Timer*)cloneTimer {
    return [[Timer alloc] initFromTimer:_timeoutTimer];
}

- (void)loadTimer:(Timer *)timer {
    [self loadTimer:timer onlyIfNew:false];
}

- (void)loadTimer:(Timer *)timer onlyIfNew:(bool)mustBeNew {
    if (!mustBeNew || _timeoutTimer == nil) {
        dispatch_sync_main(^{
            [_progressObject setProgress:[_timeoutTimer getRatioProgressThroughTick] animated:false];
        });
        _timeoutTimer = timer;
        [self startUpdating];
    } else {
        [_timeoutTimer setSecondsFrequency:[timer secondsFrequency]];
    }
}

- (void)startUpdating {
    dispatch_sync_main(^{
        if ([_updatingUi signalAll]) {
            _stopped = false;
            [self doUpdateProgress];
        }
    });
}

- (void)doUpdateProgress {
    dispatch_sync_main(^{
        if (_stopped) {
            return;
        }

        float ratioProgress;
        if (_timeoutTimer != nil) {
            ratioProgress = [_timeoutTimer getRatioProgressThroughTick];
        } else {
            ratioProgress = 1.0;
        }
        [_progressObject setProgress:ratioProgress animated:true];
        if (ratioProgress >= 1.0) {
            [_updatingUi clear];
            [_timeoutDelegate onTimedOut];
            return;
        }

        dispatch_async_main(^{
            [self doUpdateProgress];
        }, 100);
    });
}
@end