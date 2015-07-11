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
@property (strong, nonatomic) IBOutlet UILabel *displayName;
@property (strong, nonatomic) IBOutlet UIButton *buttonFinished;

@property (strong, nonatomic) IBOutlet FBSDKProfilePictureView *displayPicture;
@property Boolean isDataLoaded;
@property NSString* firstName;
@property NSString* middleName;
@property NSString* lastName;
@property NSURL* facebookUrl;
@property NSString* facebookId;

@property NSString* humanFullName;
@property NSString * humanShortName;
- (void)signalBackwards;
- (void)initialize;
@end
