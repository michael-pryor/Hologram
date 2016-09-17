//
// Created by Michael Pryor on 16/09/2016.
//

#import "TextualViewController.h"
#import "CircleProgressBar.h"
#import "Timer.h"
#import "Threading.h"
#import "ViewInteractions.h"
#import "Notifications.h"


@implementation TextualViewController {
    __weak IBOutlet CircleProgressBar *_progressCircleView;
    CircleCountdownTimer *_progressCircleViewCountdown;
    __weak IBOutlet UILabel *_tapToNotifyLabel;

    bool _notificationRequestSent;
}

- (void)viewDidLoad {
    _progressCircleViewCountdown = [[CircleCountdownTimer alloc] initWithCircleProgressBar:_progressCircleView matchingAnswerDelegate:self];
    [_progressCircleViewCountdown enableInfiniteMode];
    [_progressCircleViewCountdown loadTimer:[[Timer alloc] initWithFrequencySeconds:30 firingInitially:false]];
    [self updateTextOfNotifyLabel];
    _notificationRequestSent = false;
}

- (void)onTimedOut {
    [self requestNotification:false];
}

- (void)stop {
    [_progressCircleViewCountdown stopUpdating];
}

- (void)requestNotification:(bool)manuallyRequested {
    if (!manuallyRequested && ![[Notifications getNotificationsInstance] notificationsEnabled]) {
        return;
    }
    [[Notifications getNotificationsInstance] enableNotifications];
    _notificationRequestSent = true;
    [self updateTextOfNotifyLabel];
}
- (IBAction)onViewTap:(id)sender {
    [self requestNotification:true];
}

- (void)updateTextOfNotifyLabel {
    dispatch_sync_main(^{
        if (_notificationRequestSent) {
            [_tapToNotifyLabel setText:@"You will be notified when a match accepts you"];
            [_tapToNotifyLabel setTextColor:[UIColor blueColor]];
        } else {
            [_tapToNotifyLabel setText:@"Tap to be notified when a match accepts you"];
            [_tapToNotifyLabel setTextColor:[UIColor colorWithRed:0.75f green:0.4f blue:0.4f alpha:1.0f]]; // this is salmon, our interactive tint.
        }
    });
}

- (void)reset {
    [_progressCircleViewCountdown restart];
    _notificationRequestSent = false;
    [self updateTextOfNotifyLabel];
    [_tapToNotifyLabel setAlpha:0];
    dispatch_async_main(^{
        [ViewInteractions fadeIn:_tapToNotifyLabel completion:nil duration:0.2];
    }, 2000);
}

@end