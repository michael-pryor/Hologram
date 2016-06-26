//
// Created by Michael Pryor on 25/06/2016.
//


#import <CircleProgressBar/CircleProgressBar.h>
#import "BannedViewController.h"
#import "Threading.h"
#import "Timer.h"


@implementation BannedViewController {
    Timer * _destinationTime;

    __weak IBOutlet CircleProgressBar *_circleTimerProgress;
    __weak IBOutlet UILabel *_humanTimeStringProgress;
}
- (void)viewDidLoad {
    [self updateProgress];
}
- (void)setupNotificationSettings {
    UIUserNotificationType types = (UIUserNotificationType) (UIUserNotificationTypeBadge |
            UIUserNotificationTypeSound | UIUserNotificationTypeAlert);

    UIUserNotificationSettings *mySettings =
            [UIUserNotificationSettings settingsForTypes:types categories:nil];

    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
}

- (void)scheduleNotification:(uint)numSeconds {
    UILocalNotification *localNotif = [[UILocalNotification alloc] init];
    if (localNotif == nil)
        return;

    localNotif.fireDate = [[NSDate date] dateByAddingTimeInterval: numSeconds];
    localNotif.timeZone = [NSTimeZone defaultTimeZone];

    localNotif.alertBody = @"Your karma has regenerated, you can logon to Hologram again";
    localNotif.alertTitle = @"Hologram Karma";

    localNotif.soundName = UILocalNotificationDefaultSoundName;
    localNotif.applicationIconBadgeNumber = 1;

    [[UIApplication sharedApplication] scheduleLocalNotification:localNotif];
    NSLog(@"Scheduled local notification to take place in %d seconds", numSeconds);
}

- (void)notifyBanExpired:(uint)numSeconds {
    [self setupNotificationSettings];
    [self scheduleNotification:numSeconds];
}

- (void)updateProgress {
    if (_circleTimerProgress == nil) {
        return;
    }

    float ratioProgress = [_destinationTime getRatioProgressThroughTick];
    [_circleTimerProgress setProgress:ratioProgress animated:true];
    if (ratioProgress >= 1.0) {
        // Always will have got here via another view controller.
        dispatch_sync_main(^{
            [self.navigationController popViewControllerAnimated:YES];
        });

        return;
    }

    dispatch_async_main(^ {
        [self updateProgress];
        [_humanTimeStringProgress setText:[_destinationTime getSecondsSinceLastTickHumanString]];
    },100);
}
- (IBAction)onBackButtonPress:(id)sender {
    [self moveToFbViewController];
}

- (void)moveToFbViewController {
    dispatch_sync_main(^{
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        UIViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"FacebookView"];
        [self.navigationController pushViewController:viewController animated:YES];
    });
}

- (void)setWaitTime:(uint)numSeconds {
    NSLog(@"Blocked wait time of %d seconds loaded", numSeconds);
    _destinationTime = [[Timer alloc] initWithFrequencySeconds:numSeconds firingInitially:false];
    [self updateProgress];
}
@end