//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import "FacebookLoginViewController.h"
#import "ConnectionViewController.h"
#import "Threading.h"

@implementation FacebookLoginViewController {
    IBOutlet UISegmentedControl *_desiredGenderChooser;
    __weak IBOutlet UILabel *_facebookAskLabel;

}

- (IBAction)onFinishedButtonClick:(id)sender {
    [self _switchToChatView];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"FacebookLogin";

    _desiredGenderChooser.selectedSegmentIndex = [[SocialState getFacebookInstance] interestedInSegmentIndex];

    [_facebookAskLabel setText:@"Please allow this application to access your name and age (date of birth) from your Facebook account. This application uses only this information, and absolutely nothing else."];
    [_facebookAskLabel setHidden:true];

    [FBSDKProfile enableUpdatesOnAccessTokenChange:true];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileUpdated:) name:FBSDKProfileDidChangeNotification object:nil];
    self.loginButton.readPermissions = @[@"public_profile", @"user_birthday"];

    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
        [self _onLogin];
    } else {
        [self _updateDisplay];
    }
}

- (IBAction)onDesiredGenderChanged:(id)sender {
    [[SocialState getFacebookInstance] setInterestedInWithSegmentIndex:[_desiredGenderChooser selectedSegmentIndex]];
}

- (void)_updateDisplay {
    SocialState *state = [SocialState getFacebookInstance];

    if ([state isBasicDataLoaded]) {
        [_displayName setText:[state humanFullName]];
        [_displayPicture setProfileID:[state facebookId]];
        [_buttonFinished setEnabled:true];
        [_facebookAskLabel setHidden:true];

        [_displayName setHidden:false];
        [_displayPicture setHidden:false];
        [_buttonFinished setHidden:false];
    } else {
        [_displayName setHidden:true];
        [_displayPicture setHidden:true];
        [_buttonFinished setHidden:true];
        [_facebookAskLabel setHidden:false];

        [_displayName setText:@""];
        [_displayPicture setProfileID:nil];
        [_buttonFinished setEnabled:false];
    }
}

- (void)_switchToChatView {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"permissionsExplanationShown"]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"This app requests your permission" message:
                        @"This application connects you via audio and video to other people. This app needs permission to access your  microphone and camera to facilitate this. This app also needs permission to access your current location; this is because we try to match you with users close by.\n\nNo audio, video or location data is stored on our servers or on your device. Matches that you connect with will not receive your location data in any form."

                                                       delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"I am happy with this!", nil];
        dispatch_sync_main(^{
            [alert show];
        });
        return;
    }

    // Always will have got here via another view controller.
    dispatch_sync_main(^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if ([alertView cancelButtonIndex] != buttonIndex) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"permissionsExplanationShown"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self _switchToChatView];
    }
}

- (void)_updateInternals {
    [[SocialState getFacebookInstance] updateCoreFacebookInformation];
    if ([[SocialState getFacebookInstance] isBasicDataLoaded]) {
        NSLog(@"Logged in");
    } else {
        NSLog(@"No profile information found; may be due to logout");
    }
}

- (void)_onLogin {
    [self _updateInternals];
    [self _updateDisplay];
}

- (void)onProfileUpdated:(NSNotification *)notification {
    [self _onLogin];
}

- (void)loginButton:(FBSDKLoginButton *)loginButton didCompleteWithResult:(FBSDKLoginManagerLoginResult *)result error:(NSError *)error {
    if ([result isCancelled]) {
        NSLog(@"User cancelled login attempt");
    } else {
        NSLog(@"Logged in successfully, retrieving credentials...");
    }
}

- (void)loginButtonDidLogOut:(FBSDKLoginButton *)loginButton {
    NSLog(@"Logged out successfully");
    [[SocialState getFacebookInstance] updateCoreFacebookInformation];
}
@end
