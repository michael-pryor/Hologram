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

    SocialState *_socialState;
    __weak IBOutlet UIStackView *_loadingFacebookDetailsIndicator;
}

- (void)cancelEditingTextBoxes {
    [self.view endEditing:YES];
}

- (void)saveTextBoxes {
    [_socialState persistHumanFullName:[_fullNameTextBox text] humanShortName:[_fullNameTextBox text]];
    [_socialState persistDateOfBirthObject:[_dateOfBirthFormatter dateFromString:[_dateOfBirthTextBox text]]];
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

    [_loadingFacebookDetailsIndicator setHidden:true];

    _socialState = [SocialState getSocialInstance];
    [_socialState registerNotifier:self];

    _dateOfBirthFormatter = [[NSDateFormatter alloc] init];
    [_dateOfBirthFormatter setDateFormat:@"yyyy-MM-dd"];

    UIDatePicker *datePicker = [[UIDatePicker alloc] init];
    datePicker.datePickerMode = UIDatePickerModeDate;
    [_dateOfBirthTextBox setInputView:datePicker];
    [datePicker addTarget:self action:@selector(updateTextField:)
         forControlEvents:UIControlEventValueChanged];
    [_dateOfBirthTextBox setInputView:datePicker];

    [FBSDKProfile enableUpdatesOnAccessTokenChange:true];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileUpdated:) name:FBSDKProfileDidChangeNotification object:nil];
    self.loginButton.readPermissions = @[@"public_profile", @"user_birthday"];

    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
    }

    [self _updateDisplay];
}

- (IBAction)onDesiredGenderChanged:(id)sender {
    [[SocialState getSocialInstance] persistInterestedInWithSegmentIndex:[_desiredGenderChooser selectedSegmentIndex]];
}
- (IBAction)onOwnerGenderChanged:(id)sender {
    [[SocialState getSocialInstance] persistOwnerGenderWithSegmentIndex:[sender selectedSegmentIndex]];
}

- (void)_updateDisplay {
    NSDate * dobObject = [_socialState dobObject];
    if (dobObject != nil) {
        [(UIDatePicker *) [_dateOfBirthTextBox inputView] setDate:dobObject];
        [_dateOfBirthTextBox setText:[_socialState dobString]];
    }

    _desiredGenderChooser.selectedSegmentIndex = [_socialState interestedInSegmentIndex];
    _ownerGenderChooser.selectedSegmentIndex = [_socialState genderSegmentIndex];

    _fullNameTextBox.text = [_socialState humanFullName];
}

- (void)_switchToChatView {
    if (![[SocialState getSocialInstance] isBasicDataLoaded]) {
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

- (void)onProfileUpdated:(NSNotification *)notification {
    [[SocialState getSocialInstance] updateCoreFacebookInformation];
    if ([[SocialState getSocialInstance] isBasicDataLoaded]) {
        NSLog(@"Logged in");
    } else {
        NSLog(@"No profile information found; may be due to logout");
    }
    [self _updateDisplay];

    if (![_socialState updateGraphFacebookInformation]) {
        return;
    }

    dispatch_sync_main(^{
        [_loadingFacebookDetailsIndicator setHidden:false];
    });
}

- (void)onSocialDataLoaded:(SocialState *)state {
    [self _updateDisplay];

    dispatch_sync_main(^{
        [_loadingFacebookDetailsIndicator setHidden:true];
    });
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
    [[SocialState getSocialInstance] updateCoreFacebookInformation];
}
@end
