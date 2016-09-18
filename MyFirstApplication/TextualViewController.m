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
    id <NotificationRequest> _notificationRequestDelegate;

    bool _remoteNotificationsEnabled, _remoteNotificationsPreparing;
}

- (void)viewDidLoad {
    _progressCircleViewCountdown = [[CircleCountdownTimer alloc] initWithCircleProgressBar:_progressCircleView matchingAnswerDelegate:self];
    [_progressCircleViewCountdown enableInfiniteMode];
    [_progressCircleViewCountdown loadTimer:[[Timer alloc] initWithFrequencySeconds:15 firingInitially:false]];
    [self updateTextOfNotifyLabel];
    _remoteNotificationsEnabled = false;
    _remoteNotificationsPreparing = false;
}

- (void)onTimedOut {
    [self requestNotification:false];
}

- (void)stop {
    [_progressCircleViewCountdown stopUpdating];
}

- (void)requestNotification:(bool)manuallyRequested {
    if ((!manuallyRequested && ![[Notifications getNotificationsInstance] notificationsEnabled]) || (_remoteNotificationsPreparing || _remoteNotificationsEnabled)) {
        return;
    }
    _remoteNotificationsPreparing = true;
    [[Notifications getNotificationsInstance] enableNotifications];
    [[Notifications getNotificationsInstance] registerForRemoteNotificationsWithCallback:self];
}

- (IBAction)onViewTap:(id)sender {
    [self requestNotification:true];
}

- (void)updateTextOfNotifyLabel {
    dispatch_sync_main(^{
        if (_remoteNotificationsEnabled) {
            [ViewInteractions fadeOut:_tapToNotifyLabel completion:^(BOOL completed){
                [_tapToNotifyLabel setText:@"You will be notified when a match accepts you"];

                [ViewInteractions fadeIn:_tapToNotifyLabel completion:^(BOOL completedTwo){
                    [_progressCircleView setProgressBarProgressColor:[UIColor greenColor]];
                } duration:0.4f];
            } duration:0.4f];
        } else {
            [_tapToNotifyLabel setText:@"Tap to be notified"];
            [_progressCircleView setProgressBarProgressColor:[UIColor orangeColor]];
        }
    });
}

- (void)reset {
    [_progressCircleViewCountdown reset];
    _remoteNotificationsEnabled = false;
    _remoteNotificationsPreparing = false;
    [self updateTextOfNotifyLabel];
    [_tapToNotifyLabel setAlpha:0];
    dispatch_async_main(^{
        [ViewInteractions fadeIn:_tapToNotifyLabel completion:nil duration:1];
    }, 500);
}

- (void)setNotificationRequestDelegate:(id <NotificationRequest>)notificationRequestDelegate {
    _notificationRequestDelegate = notificationRequestDelegate;
}

- (void)onRemoteNotificationRegistrationSuccess:(NSData *)deviceToken {
    _remoteNotificationsPreparing = false;
    _remoteNotificationsEnabled = true;
    [self updateTextOfNotifyLabel];

    [_notificationRequestDelegate onRemoteNotificationRegistrationSuccess:deviceToken];
}

- (void)onRemoteNotificationRegistrationFailure:(NSString *)description {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Notifications Problem" message:[NSString stringWithFormat:@"Could not register for notifications, reason: %@", description] preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction * okAction = [UIAlertAction
            actionWithTitle:@"OK"
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        _remoteNotificationsPreparing = false;
                    }];
    [alertController addAction:okAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)start {
    [_progressCircleViewCountdown startUpdating];
}
@end