//
// Created by Michael Pryor on 10/07/2016.
//

#import "CircleCountdownTimer.h"
#import "CircleProgressBar.h"
#import "Signal.h"
#import "Timer.h"
#import "Threading.h"

@implementation CircleCountdownTimer {
    CircleProgressBar *_progressObject;
    Timer *_timeoutTimer;
    Signal *_updatingUi;
    id <TimeoutDelegate> _timeoutDelegate;
    bool _stopped;

    bool _infiniteModeEnabled;
    bool _infiniteBackwardsLeg;
}

- (id)initWithCircleProgressBar:(CircleProgressBar *)circleProgressBar matchingAnswerDelegate:(id <TimeoutDelegate>)matchingAnswerDelegate {
    self = [super init];
    if (self) {
        _progressObject = circleProgressBar;
        _timeoutDelegate = matchingAnswerDelegate;
        _updatingUi = [[Signal alloc] initWithFlag:false];
        _timeoutTimer = nil;
        _stopped = false;
        _infiniteModeEnabled = false;
        _infiniteBackwardsLeg = false;
    }
    return self;
}

- (void)restart {
    dispatch_sync_main(^{
        [_progressObject setProgress:0 animated:false];
    });

    _infiniteBackwardsLeg = false;
    if (_timeoutTimer != nil) {
        [_timeoutTimer reset];
        [self startUpdating];
    }
}

- (void)enableInfiniteMode {
    _infiniteModeEnabled = true;
}

- (void)stopUpdating {
    dispatch_sync_main(^{
        if ([_updatingUi clear]) {
            _stopped = true;
        }
    });
}

- (Timer *)cloneTimer {
    return [[Timer alloc] initFromTimer:_timeoutTimer];
}

- (void)loadTimer:(Timer *)timer {
    [self loadTimer:timer onlyIfNew:false];
}

- (void)loadTimer:(Timer *)timer onlyIfNew:(bool)mustBeNew {
    if (!mustBeNew || _timeoutTimer == nil) {
        dispatch_sync_main(^{
            float progress = [_timeoutTimer getRatioProgressThroughTick];
            [_progressObject setProgress:progress animated:false];
        });
        _timeoutTimer = timer;
        if (![_progressObject hintHidden]) {
            [_progressObject setHintTextGenerationBlock:^NSString *(CGFloat progress) {
                int secondsLeft = (int) [timer getSecondsUntilNextTick];
                return [NSString stringWithFormat:@"%d", secondsLeft];
            }];
        }

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
            ratioProgress = 1.0f;
        }

        float ratioProgressForUi = ratioProgress;
        if (_infiniteModeEnabled && _infiniteBackwardsLeg) {
            ratioProgressForUi = 1.0f - ratioProgress;
        }

        [_progressObject setProgress:ratioProgressForUi animated:true];
        if (ratioProgress >= 1.0f) {
            if (!_infiniteModeEnabled) {
                [self stopUpdating];
            } else {
                _infiniteBackwardsLeg = !_infiniteBackwardsLeg;
                [_timeoutTimer reset];
            }
            [_timeoutDelegate onTimedOut];

            if (!_infiniteModeEnabled) {
                return;
            }
        }

        dispatch_async_main(^{
            [self doUpdateProgress];
        }, 200);
    });
}
@end