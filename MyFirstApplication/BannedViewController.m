//
// Created by Michael Pryor on 25/06/2016.
//


#import <CircleProgressBar/CircleProgressBar.h>
#import <StoreKit/StoreKit.h>
#import "BannedViewController.h"
#import "Threading.h"
#import "Timer.h"
#import "ViewInteractions.h"
#import "BanPaymentsViewController.h"

#define kPushNotificationRequestAlreadySeen @"pushNotificationsAlreadySeen"

@implementation BannedViewController {
    Timer *_destinationTime;

    __weak IBOutlet CircleProgressBar *_circleTimerProgress;
    __weak IBOutlet UILabel *_humanTimeStringProgress;
    __weak IBOutlet UIButton *_notifyButton;
    __weak IBOutlet UILabel *_tapToSkipLabel;

    bool _schedulePushNotification;
    bool _isScreenInUse;

    __weak IBOutlet UIView *_purchaseView;
    __weak IBOutlet BanPaymentsViewController *_purchaseViewController;
    SKProduct *_paymentProduct;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"Banned";

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillRetakeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    _isScreenInUse = false;

    _purchaseViewController = self.childViewControllers[0];
    [_purchaseViewController setOnFinishedFunc:^{
        [self onPaymentsViewTap:self];
    }];
    if (_paymentProduct != nil) {
        [_purchaseViewController setProduct:_paymentProduct];
    }
    if ([self canAcceptPayments]) {
        [_circleTimerProgress setHintTextColor:[UIColor greenColor]];
        [_tapToSkipLabel setHidden:false];
    } else {
        [_circleTimerProgress setHintTextColor:[UIColor redColor]];
        [_tapToSkipLabel setHidden:true];
    }
}

- (void)appWillResignActive:(NSNotification *)note {
    if (!_isScreenInUse) {
        return;
    }

    [self onScreenNoLongerVisible];
}

- (void)appWillRetakeActive:(NSNotification *)note {
    if (!_isScreenInUse) {
        return;
    }

    [self onScreenVisible];
}

- (void)viewDidAppear:(BOOL)animated {
    _isScreenInUse = true;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPushNotificationRequestAlreadySeen]) {
        [self onPushNotificationsEnabled];
    } else {
        _schedulePushNotification = false;
    }

    if ([self canAcceptPayments]) {
        [_tapToSkipLabel setAlpha:1.0f];
        [ViewInteractions fadeOut:_tapToSkipLabel completion:nil duration:10];
    }

    [self updateProgress:true];
    [self onScreenVisible];
}

- (void)viewDidDisappear:(BOOL)animated {
    _isScreenInUse = false;
    [self onScreenNoLongerVisible];
}

- (void)onScreenNoLongerVisible {
    if (_schedulePushNotification) {
        [self notifyBanExpired:(uint) [_destinationTime getSecondsUntilNextTick]];
    }
}

- (void)onScreenVisible {
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
}

- (void)setupNotificationSettings {
    UIUserNotificationType types = (UIUserNotificationType) (UIUserNotificationTypeBadge |
            UIUserNotificationTypeSound | UIUserNotificationTypeAlert);

    UIUserNotificationSettings *mySettings =
            [UIUserNotificationSettings settingsForTypes:types categories:nil];

    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
}

- (void)onPushNotificationsEnabled {
    _schedulePushNotification = true;
    dispatch_sync_main(^{
        [_notifyButton setEnabled:false];
        [_notifyButton setTitle:@"You will be notified when ready" forState:UIControlStateNormal];
    });
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPushNotificationRequestAlreadySeen];
}

- (void)scheduleNotification:(uint)numSeconds {
    UILocalNotification *localNotif = [[UILocalNotification alloc] init];
    if (localNotif == nil)
        return;

    localNotif.fireDate = [[NSDate date] dateByAddingTimeInterval:numSeconds];
    localNotif.timeZone = [NSTimeZone defaultTimeZone];

    localNotif.alertBody = @"Your karma has regenerated, you can logon to Hologram again";
    localNotif.alertTitle = @"Hologram Karma";

    localNotif.soundName = UILocalNotificationDefaultSoundName;
    localNotif.applicationIconBadgeNumber = 1;

    [[UIApplication sharedApplication] scheduleLocalNotification:localNotif];
    NSLog(@"Scheduled local notification to take place in %d seconds", numSeconds);
}

- (IBAction)onSwipeBackwards:(id)sender {
    [self moveToFbViewController];
}

- (void)notifyBanExpired:(uint)numSeconds {
    [self setupNotificationSettings];
    [self scheduleNotification:numSeconds];
}

- (IBAction)onNotifyButtonPress:(id)sender {
    [self setupNotificationSettings]; // so we get the permissions dialog.
    [self onPushNotificationsEnabled];
}

- (void)updateProgress:(bool)updateNow {
    if (_circleTimerProgress == nil) {
        return;
    }

    float ratioProgress = [_destinationTime getRatioProgressThroughTick];
    [_circleTimerProgress setProgress:ratioProgress animated:true];
    if (ratioProgress >= 1.0) {
        // Always will have got here via another view controller.
        dispatch_sync_main(^{
            [self.navigationController popToRootViewControllerAnimated:YES];
        });

        return;
    }

    if (updateNow) {
        dispatch_sync_main(^{
            [self doUpdateProgress];
        });
    } else {
        dispatch_async_main(^{
            [self doUpdateProgress];
        }, 500);
    }
}

- (void)doUpdateProgress {
    [_humanTimeStringProgress setText:[_destinationTime getSecondsSinceLastTickHumanString]];
    [self updateProgress:false];
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

- (IBAction)onProgressTap:(id)sender {
    if (![self canAcceptPayments]) {
        return;
    }

    dispatch_sync_main(^{
        [ViewInteractions fadeOut:_circleTimerProgress thenIn:_purchaseView duration:0.3f];
    });
}

- (void)onPaymentsViewTap:(id)sender {
    dispatch_sync_main(^{
        [ViewInteractions fadeOut:_purchaseView thenIn:_circleTimerProgress duration:0.3f];
    });
}

- (bool)canAcceptPayments {
    return _paymentProduct != nil && [SKPaymentQueue canMakePayments];
}

- (void)setWaitTime:(uint)numSeconds paymentProduct:(SKProduct *)product {
    NSLog(@"Blocked wait time of %d seconds loaded", numSeconds);
    _destinationTime = [[Timer alloc] initWithFrequencySeconds:numSeconds firingInitially:false];
    _paymentProduct = product;
}
@end