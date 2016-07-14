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
#import <GAITrackedViewController.h>
#import "SocialState.h"

@interface FacebookLoginViewController : GAITrackedViewController <UITextFieldDelegate, UITextViewDelegate, FBSDKLoginButtonDelegate, UIAlertViewDelegate, SocialStateDataLoadNotification, UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@property(weak, nonatomic) IBOutlet FBSDKLoginButton *loginButton;

@property(nonatomic,strong) UIDatePicker *dateOfBirthDatePicker;
@end
