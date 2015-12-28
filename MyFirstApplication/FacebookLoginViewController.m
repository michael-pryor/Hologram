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
}

- (IBAction)onFinishedButtonClick:(id)sender {
    [self _switchToChatView];
}

- (void)viewDidLoad {
    [super viewDidLoad];

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
    SocialState *state = [SocialState getFacebookInstance];
    if ([_desiredGenderChooser selectedSegmentIndex] == 0) {
        [state setInterestedIn:@"male"];
    } else if ([_desiredGenderChooser selectedSegmentIndex] == 1) {
        [state setInterestedIn:@"female"];
    } else if ([_desiredGenderChooser selectedSegmentIndex] == 2) {
        [state setInterestedIn:nil];
    }
}

- (void)_updateDisplay {
    SocialState *state = [SocialState getFacebookInstance];

    if ([state isBasicDataLoaded]) {
        [_displayName setText:[state humanFullName]];
        [_displayPicture setProfileID:[state facebookId]];
        [_buttonFinished setEnabled:true];

        [_displayName setHidden:false];
        [_displayPicture setHidden:false];
        [_buttonFinished setHidden:false];

        if ([state interestedInI] == BOTH) {
            _desiredGenderChooser.selectedSegmentIndex = 2;
        } else if ([state interestedInI] == FEMALE) {
            _desiredGenderChooser.selectedSegmentIndex = 1;
        } else if ([state interestedInI] == MALE) {
            _desiredGenderChooser.selectedSegmentIndex = 0;
        }
    } else {
        [_displayName setHidden:true];
        [_displayPicture setHidden:true];
        [_buttonFinished setHidden:true];

        [_displayName setText:@""];
        [_displayPicture setProfileID:nil];
        [_buttonFinished setEnabled:false];

        _desiredGenderChooser.selectedSegmentIndex = 2; // BOTH
    }
}

- (void)_switchToChatView {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"permissionsExplanationShown"]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"This app requests your permission" message:
                               @"This application connects you via audio and video to other people. This app needs permission to access your  microphone and camera to facilitate this. This app also needs permission to access your current location; this is because we try to match you with users close by.\n\nNo audio, video or location data is stored on our servers or on your device. Matches that you connect with will not receive your location data in any form."

                                                       delegate:self cancelButtonTitle: @"Cancel" otherButtonTitles: @"I am happy with this!", nil];
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
    [[SocialState getFacebookInstance] updateFacebook];
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
    [[SocialState getFacebookInstance] updateFacebook];
}
@end
