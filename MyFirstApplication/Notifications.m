//
// Created by Michael Pryor on 13/08/2016.
//

#import "Notifications.h"

#define kPushNotificationRequestAlreadySeen @"pushNotificationsAlreadySeen"
static Notifications *notificationsInstance = nil;
@implementation Notifications {

}

- (id)init {
    self = [super init];
    if (self) {
        _notificationsEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kPushNotificationRequestAlreadySeen];
    }
    return self;
}

// This will trigger permissions dialog box if necessary.
- (void)enableNotifications {
    UIUserNotificationType types = (UIUserNotificationType) (UIUserNotificationTypeBadge |
            UIUserNotificationTypeSound | UIUserNotificationTypeAlert);

    UIUserNotificationSettings *mySettings =
            [UIUserNotificationSettings settingsForTypes:types categories:nil];

    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPushNotificationRequestAlreadySeen];
}



+ (Notifications *)getNotificationsInstance {
    @synchronized (self) {
        if (notificationsInstance == nil) {
            notificationsInstance = [[Notifications alloc] init];
        }

        return notificationsInstance;
    }
}
@end