//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import "FacebookLoginViewController.h"
#import "Threading.h"
#import "DobParsing.h"

static CGFloat _lastScrollViewPosition;

@implementation FacebookLoginViewController {
    IBOutlet UISegmentedControl *_desiredGenderChooser;
    __weak IBOutlet UITextField *_dateOfBirthTextBox;

    __weak IBOutlet UITextField *_fullNameTextBox;
    __weak IBOutlet UISegmentedControl *_ownerGenderChooser;

    SocialState *_socialState;
    __weak IBOutlet UIStackView *_loadingFacebookDetailsIndicator;
    __weak IBOutlet UIImageView *_profilePicture;
    __weak IBOutlet UITextView *_callingCardText;

    __weak IBOutlet UIScrollView *_scrollView;
}

+ (void)initialize {
    if (self == [FacebookLoginViewController class]) {
        _lastScrollViewPosition = 0;
    }
}

- (void)cancelEditingTextBoxes {
    [self.view endEditing:YES];
}

- (IBAction)onProfilePictureTap:(id)sender {
    UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
    imagePickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePickerController.delegate = self;
    [self presentViewController:imagePickerController animated:YES completion:nil];
    
    [self onViewControllerTap:sender];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [_socialState persistProfilePictureImage:[info valueForKey:UIImagePickerControllerOriginalImage]];
    dispatch_sync_main(^{
        [_profilePicture setImage:[_socialState profilePictureImage]];
    });

    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTextBoxes {
    [_socialState persistHumanFullName:[_fullNameTextBox text] humanShortName:[_fullNameTextBox text]];
    [_socialState persistDateOfBirthObject:[DobParsing getDateObjectFromTextBoxString:[_dateOfBirthTextBox text]]];
    [_socialState persistCallingCardText:[NSString stringWithFormat:@"%@",[_callingCardText text]]];
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    _lastScrollViewPosition = scrollView.contentOffset.y;
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

- (IBAction)onSwipeGesture:(UISwipeGestureRecognizer *)recognizer {
    [self _switchToChatView];
}

- (void)updateTextField:(UIDatePicker *)sender {
    _dateOfBirthTextBox.text = [DobParsing getTextBoxStringFromDateObject:sender.date];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"FacebookLogin";
    [_loadingFacebookDetailsIndicator setHidden:true];

    _socialState = [SocialState getSocialInstance];
    [_socialState registerNotifier:self];
    
    [_scrollView setContentOffset: CGPointMake(0,_lastScrollViewPosition)];
    
    _dateOfBirthDatePicker = [[UIDatePicker alloc] init]; // needs to be retained.
    _dateOfBirthDatePicker.datePickerMode = UIDatePickerModeDate;
    [_dateOfBirthTextBox setInputView:_dateOfBirthDatePicker];
    [_dateOfBirthDatePicker addTarget:self action:@selector(updateTextField:)
                     forControlEvents:UIControlEventValueChanged];
    [_dateOfBirthTextBox setInputView:_dateOfBirthDatePicker];

    [_profilePicture.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_profilePicture.layer setBorderWidth: 2.0];

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
    NSDate *dobObject = [_socialState dobObject];
    if (dobObject != nil) {
        [(UIDatePicker *) [_dateOfBirthTextBox inputView] setDate:dobObject];
        [_dateOfBirthTextBox setText:[_socialState dobString]];
    }

    _desiredGenderChooser.selectedSegmentIndex = [_socialState interestedInSegmentIndex];
    _ownerGenderChooser.selectedSegmentIndex = [_socialState genderSegmentIndex];

    _fullNameTextBox.text = [_socialState humanFullName];

    [_profilePicture setImage:[_socialState profilePictureImage]];
    
    [_callingCardText setText:[_socialState callingCardText]];
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
    NSLog(@"Facebook profile updated notification received, updating information");

    [[SocialState getSocialInstance] updateFromFacebookCore];
    [self _updateDisplay];

    if (![_socialState updateFromFacebookGraph]) {
        return;
    }

    dispatch_sync_main(^{
        [_loadingFacebookDetailsIndicator setAlpha:0];
    });
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    // Prevent crashing undo bug – see note below.
    if (range.length + range.location > textView.text.length) {
        return NO;
    }

    int MAX_LENGTH = 300;
    NSUInteger newLength = (textView.text.length - range.length) + text.length;
    if(newLength <= MAX_LENGTH)
    {
        return YES;
    } else {
        NSUInteger emptySpace = MAX_LENGTH - (textView.text.length - range.length);
        textView.text = [[[textView.text substringToIndex:range.location]
                stringByAppendingString:[text substringToIndex:emptySpace]]
                stringByAppendingString:[textView.text substringFromIndex:(range.location + range.length)]];
        return NO;
    }
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Prevent crashing undo bug – see note below.
    if (range.length + range.location > textField.text.length) {
        return NO;
    }

    NSUInteger newLength = [textField.text length] + [string length] - range.length;

    if (textField == _fullNameTextBox) {
        return newLength <= 50;
    } else {
        return YES;
    }
}

- (void)onSocialDataLoaded:(SocialState *)state {
    [self _updateDisplay];

    dispatch_sync_main(^{
        [_loadingFacebookDetailsIndicator setAlpha:1];
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
}
@end
