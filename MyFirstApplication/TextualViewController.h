//
// Created by Michael Pryor on 16/09/2016.
//

#import <Foundation/Foundation.h>
#import "CircleCountdownTimer.h"
#import "SingleViewCollection.h"

@protocol NotificationRequest;

@interface TextualViewController : UIViewController<TimeoutDelegate, NotificationRequest>
- (void)stop;

- (void)reset;

- (void)setNotificationRequestDelegate:(id <NotificationRequest>)notificationRequestDelegate;

- (void)start;
@end