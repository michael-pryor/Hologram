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

@interface FacebookLoginViewController : UIViewController<FBSDKLoginButtonDelegate>
// In your view header file:
@property (weak, nonatomic) IBOutlet FBSDKLoginButton *loginButton;
@property NSString* firstName;
@property NSString* middleName;
@property NSString* lastName;
@property NSURL* facebookUrl;

@property NSString* humanFullName;
@property NSString * humanShortName;

@end
