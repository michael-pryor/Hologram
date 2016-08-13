//
// Created by Michael Pryor on 13/08/2016.
//

#import <Foundation/Foundation.h>


@interface Notifications : NSObject
@property (readonly, atomic) bool notificationsEnabled;

+ (Notifications *)getNotificationsInstance;

- (void)enableNotifications;
@end