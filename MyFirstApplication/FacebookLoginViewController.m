//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import "FacebookLoginViewController.h"

@implementation FacebookLoginViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    
    //[FBSDKProfile enableUpdatesOnAccessTokenChange:YES];

    // In your viewDidLoad method:
    self.loginButton.readPermissions = @[@"public_profile", @"email", @"user_friends", @"user_birthday"];
    
    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
        // User is logged in, do work such as go to next view controller.
    }
}
@end
