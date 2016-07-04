//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>
#import "GAITrackedViewController.h"


@interface FacebookSharedViewController : GAITrackedViewController
- (void)setRemoteFullName:(NSString *)remoteFullName remoteCallingText:(NSString *)remoteCallingText remoteProfilePicture:(UIImage *)remoteProfilePicture localFullName:(NSString *)localFullName localCallingText:(NSString *)localCallingText localProfilePicture:(UIImage *)localProfilePicture;

- (void)enableTutorialModeWithFullName:(NSString *)name callingText:(NSString *)callingText profilePicture:(UIImage *)picture;
@end