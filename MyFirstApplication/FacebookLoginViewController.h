//
//  FacebookLoginViewController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import <Foundation/Foundation.h>
#import <FBSDKLoginKit/FBSDKLoginKit.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import "GAITrackedViewController.h"

@interface FacebookLoginViewController : GAITrackedViewController <UITextFieldDelegate, FBSDKLoginButtonDelegate, UIAlertViewDelegate>
@property(weak, nonatomic) IBOutlet FBSDKLoginButton *loginButton;
@property(strong, nonatomic) IBOutlet UILabel *displayName;
@property(strong, nonatomic) IBOutlet FBSDKProfilePictureView *displayPicture;
@end
