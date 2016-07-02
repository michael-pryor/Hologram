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
    __weak IBOutlet UIImageView *_buttonDone;
    __weak IBOutlet UITextField *_dateOfBirthTextBox;

    NSDateFormatter *_dateOfBirthFormatter;
    __weak IBOutlet UITextField *_fullNameTextBox;
    __weak IBOutlet UISegmentedControl *_ownerGenderChooser;
}

- (void)cancelEditingTextBoxes {
    [self.view endEditing:YES];
}

- (void)saveTextBoxes {

}

- (IBAction)onTextBoxDonePressed:(id)sender {
    [self cancelEditingTextBoxes];
    [self saveTextBoxes];
}
- (IBAction)onViewControllerTap:(id)sender {
    [self cancelEditingTextBoxes];
    [self saveTextBoxes];
}


- (IBAction)onFinishedButtonClick:(id)sender {
    [self _switchToChatView];
}
- (IBAction)onSwipeGesture:(UISwipeGestureRecognizer *)recognizer  {
    [self _switchToChatView];
}

-(void)updateTextField:(UIDatePicker *)sender{
    _dateOfBirthTextBox.text = [_dateOfBirthFormatter stringFromDate:sender.date];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"FacebookLogin";

    _dateOfBirthFormatter = [[NSDateFormatter alloc] init];
    [_dateOfBirthFormatter setDateFormat:@"yyyy-MM-dd"];

    UIDatePicker *datePicker = [[UIDatePicker alloc] init];
    datePicker.datePickerMode = UIDatePickerModeDate;
    [_dateOfBirthTextBox setInputView:datePicker];
    [datePicker addTarget:self action:@selector(updateTextField:)
         forControlEvents:UIControlEventValueChanged];
    [_dateOfBirthTextBox setInputView:datePicker];

    SocialState *socialState = [SocialState getFacebookInstance];
    _desiredGenderChooser.selectedSegmentIndex = [socialState interestedInSegmentIndex];
    _ownerGenderChooser.selectedSegmentIndex = [socialState genderSegmentIndex];

    _fullNameTextBox.text = [socialState humanFullName];

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
    [[SocialState getFacebookInstance] persistInterestedInWithSegmentIndex:[_desiredGenderChooser selectedSegmentIndex]];
}
- (IBAction)onOwnerGenderChanged:(id)sender {
    [[SocialState getFacebookInstance] setOwnerGenderWithSegmentIndex:[sender selectedSegmentIndex]];
}

- (void)_updateDisplay {
    SocialState *state = [SocialState getFacebookInstance];

    if ([state isBasicDataLoaded]) {
        dispatch_sync_main(^{
            [_displayName setText:[state humanFullName]];
            //[_displayPicture setProfileID:[state persistedUniqueId]];

            [_displayName setHidden:false];
            [_displayPicture setHidden:false];
            [_buttonDone setHidden:false];
        });
    } else {
        dispatch_sync_main(^{
            [_displayName setHidden:true];
            [_displayPicture setHidden:true];
            [_buttonDone setHidden:true];

            [_displayName setText:@""];
            [_displayPicture setProfileID:nil];
        });
    }
}

- (void)_switchToChatView {
    if (![[SocialState getFacebookInstance] isBasicDataLoaded]) {
        return;
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"permissionsExplanationShown"]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Hologram Permissions" message:
                        @"Hologram needs access to your camera, microphone and location so that it can setup video conversations with people in your area."
                                                       delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"I am happy with this!", nil];
        dispatch_sync_main(^{
            [alert show];
        });
        return;
    }

    // Always will have got here via another view controller.
    dispatch_sync_main(^{
        [self.navigationController popToRootViewControllerAnimated:YES];
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
