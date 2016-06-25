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
}
- (void)viewDidLoad {
    //_destinationTime = nil;
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
    float secondsSinceLastTick = [_destinationTime getPercentageProgressThroughTick] / 100.0;
    [_circleTimerProgress setProgress:secondsSinceLastTick animated:true];

    dispatch_async_main(^ {
        [self updateProgress];
    },1000);
}

- (void)setWaitTime:(uint)numSeconds {
    NSLog(@"Wait time of %d seconds loaded", numSeconds);
    _destinationTime = [[Timer alloc] initWithFrequencySeconds:numSeconds firingInitially:false];
    [self updateProgress];
}
@end