//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>
#import "GAITrackedViewController.h"


@interface FacebookSharedViewController : GAITrackedViewController
- (void)setRemoteFullName:(NSString *)remoteFullName remoteProfilePicture:(UIImage *)remoteProfilePicture remoteCallingText:(NSString *)remoteCallingText localFullName:(NSString *)localFullName localProfilePicture:(UIImage *)localProfilePicture localCallingText:(NSString *)localCallingText;
@end