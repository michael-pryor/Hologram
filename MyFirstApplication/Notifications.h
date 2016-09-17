//
// Created by Michael Pryor on 13/08/2016.
//

#import <Foundation/Foundation.h>

@protocol NotificationRequest
- (void)onNotificationRequested;
@end

@interface Notifications : NSObject
@property (readonly, atomic) bool notificationsEnabled;

+ (Notifications *)getNotificationsInstance;

- (void)enableNotifications;

- (UILocalNotification *)getLocalNotificationWithId:(NSString*)idString;

- (void)cancelNotificationsWithId:(NSString*)idString;
@end