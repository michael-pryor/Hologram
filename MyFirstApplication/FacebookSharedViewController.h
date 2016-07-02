//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>
#import "GAITrackedViewController.h"


@interface FacebookSharedViewController : GAITrackedViewController
- (void)setRemoteFacebookId:(NSString *)remoteFacebookId remoteProfileUrl:(NSString *)remoteProfileUrl remoteFullName:(NSString *)remoteFullName localFacebookId:(NSString *)localFacebookId localFullName:(NSString *)localFullName;
@end