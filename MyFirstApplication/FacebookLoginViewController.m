//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import "FacebookLoginViewController.h"
#import "ConnectionViewController.h"
#import "SocialState.h"

@implementation FacebookLoginViewController {
    Boolean _initialized;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}
- (IBAction)onFinishedButtonClick:(id)sender {
    [self _switchToChatView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileUpdated:) name:FBSDKProfileDidChangeNotification object:nil];
    self.loginButton.readPermissions = @[@"public_profile", @"email", @"user_friends", @"user_birthday"];

    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
        [self _onLogin];
    } else {
        [self _updateDisplay];
    }
}

- (void)_updateDisplay {
    SocialState* state = [SocialState getFacebookInstance];
    
    if([state isDataLoaded]) {
        [_displayName setText:[state humanFullName]];
        [_displayPicture setProfileID:[state facebookId]];
        [_buttonFinished setEnabled:true];
    } else {
        [_displayName setText:@"Who are you?"];
        [_displayPicture setProfileID:nil];
        [_buttonFinished setEnabled:false];
    }
}

- (void)_switchToChatView {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    ConnectionViewController* viewController = (ConnectionViewController*)[storyboard instantiateViewControllerWithIdentifier:@"ConnectionView"];
    [self presentViewController:viewController animated:YES completion:nil];
}

- (void)_updateInternals {
    [[SocialState getFacebookInstance] updateFacebook];
    if([[SocialState getFacebookInstance] isDataLoaded]) {
        NSLog(@"Logged in");
    } else {
        NSLog(@"No profile information found; may be due to logout");
    }
}

- (void)_onLogin {
    [self _updateInternals];
    [self _updateDisplay];
}

- (void)onProfileUpdated:(NSNotification*)notification {
    [self _onLogin];
}

- (void)loginButton:(FBSDKLoginButton*)loginButton didCompleteWithResult:(FBSDKLoginManagerLoginResult*)result error:(NSError*)error {
    if ([result isCancelled]) {
        NSLog(@"User cancelled login attempt");
    } else {
        NSLog(@"Logged in successfully, retrieving credentials...");
    }
}

- (void)loginButtonDidLogOut:(FBSDKLoginButton*)loginButton {
    NSLog(@"Logged out successfully");
    [[SocialState getFacebookInstance] updateFacebook];
}
@end
