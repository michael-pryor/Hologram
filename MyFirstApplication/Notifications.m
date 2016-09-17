//
// Created by Michael Pryor on 13/08/2016.
//

#import "Notifications.h"

#define kPushNotificationRequestAlreadySeen @"pushNotificationsAlreadySeen"
#define kNotificationId @"notificationId"
static Notifications *notificationsInstance = nil;

@implementation Notifications {
    NSMutableSet *_remoteNotificationRequesters;
}

- (id)init {
    self = [super init];
    if (self) {
        _notificationsEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kPushNotificationRequestAlreadySeen];
        _remoteNotificationRequesters = [[NSMutableSet alloc] init];
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
    _notificationsEnabled = true;
}

- (UILocalNotification *)getLocalNotificationWithId:(NSString *)idString {
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.userInfo = @{kNotificationId : idString};
    return notification;
}

- (void)cancelNotificationsWithId:(NSString *)idString {
    for (UILocalNotification *localNotification in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
        NSDictionary *dictionary = [localNotification userInfo];
        if (dictionary == nil) {
            continue;
        }

        NSString *notificationId = dictionary[kNotificationId];
        if (notificationId == nil) {
            continue;
        }

        if ([idString isEqualToString:notificationId]) {
            [[UIApplication sharedApplication] cancelLocalNotification:localNotification];
        }
    }
}

- (void)registerForRemoteNotificationsWithCallback:(id <NotificationRequest>)notificationRequest {
    [_remoteNotificationRequesters addObject:notificationRequest];
    [[UIApplication sharedApplication] registerForRemoteNotifications];
}

+ (Notifications *)getNotificationsInstance {
    @synchronized (self) {
        if (notificationsInstance == nil) {
            notificationsInstance = [[Notifications alloc] init];
        }

        return notificationsInstance;
    }
}

- (void)onRemoteRegisterFailureWithError:(NSError *)error {
    @synchronized (self) {
        NSLog(@"Failed to register for remote notifications: %@", [error localizedDescription]);
        for (id <NotificationRequest> request in _remoteNotificationRequesters) {
            [request onRemoteNotificationRegistrationFailure:[error localizedDescription]];
        }
        [_remoteNotificationRequesters removeAllObjects];
    }
}

- (void)onRemoteRegisterSuccessWithDeviceToken:(NSData *)deviceToken {
    @synchronized (self) {
        NSLog(@"Successfully registered for remote notifications");
        for (id <NotificationRequest> request in _remoteNotificationRequesters) {
            [request onRemoteNotificationRegistrationSuccess:deviceToken];
        }
        [_remoteNotificationRequesters removeAllObjects];
    }
}
@end