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
    __weak IBOutlet UIButton *_startButton;
    __weak IBOutlet UIView *_startButtonView;


    __weak IBOutlet UILabel *_warningName;
    __weak IBOutlet UILabel *_warningDateOfBirth;
    __weak IBOutlet UILabel *_warningCallingCardPicture;
    __weak IBOutlet UILabel *_warningGender;
    __weak IBOutlet UILabel *_warningAgeRestriction;
    __weak IBOutlet UILabel *_warningEula;

    bool _waitingForEulaCompletion;
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
    [self validateForm];
}


- (void)validateForm {
    dispatch_sync_main(^{
        bool isProblem = false;
        bool isCurrentItemProblem;

        isProblem = isProblem | (isCurrentItemProblem = [[_fullNameTextBox text] length] == 0);
        [_warningName setHidden:!isCurrentItemProblem];

        isProblem = isProblem | (isCurrentItemProblem = [[_dateOfBirthTextBox text] length] == 0);
        [_warningDateOfBirth setHidden:!isCurrentItemProblem];

        bool isAgeSet = !isCurrentItemProblem;
        isProblem = isProblem | (isCurrentItemProblem = isAgeSet && [_socialState age] < MINIMUM_AGE);
        [_warningAgeRestriction setHidden:!isCurrentItemProblem];

        isProblem = isProblem | (isCurrentItemProblem = [_ownerGenderChooser selectedSegmentIndex] == UISegmentedControlNoSegment);
        [_warningGender setHidden:!isCurrentItemProblem];

        isProblem = isProblem | (isCurrentItemProblem = [_socialState profilePictureImage] == nil);
        [_warningCallingCardPicture setHidden:!isCurrentItemProblem];

        [_startButton setEnabled:!isProblem];
        if (isProblem) {
            [_startButtonView setAlpha:0.5];
            [_warningEula setHidden:true];
        } else {
            [_startButtonView setAlpha:1.0];
            [_warningEula setHidden: [_socialState hasAcceptedEula]];
        }
    });
}

- (void)saveTextBoxes {
    NSString *fullName = [_fullNameTextBox text];
    NSString *shortName = [fullName componentsSeparatedByString:@" "][0];
    [_socialState persistHumanFullName:fullName humanShortName:shortName];
    [_socialState persistDateOfBirthObject:[DobParsing getDateObjectFromTextBoxString:[_dateOfBirthTextBox text]]];
    [_socialState persistCallingCardText:[NSString stringWithFormat:@"%@", [_callingCardText text]]];

    [self validateForm];
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
    [self validateForm];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"FacebookLogin";

    _waitingForEulaCompletion = false;
    [_loadingFacebookDetailsIndicator setAlpha:0];

    _socialState = [SocialState getSocialInstance];
    [_socialState registerNotifier:self];

    _dateOfBirthDatePicker = [[UIDatePicker alloc] init]; // needs to be retained.
    _dateOfBirthDatePicker.datePickerMode = UIDatePickerModeDate;
    [_dateOfBirthTextBox setInputView:_dateOfBirthDatePicker];
    [_dateOfBirthDatePicker addTarget:self action:@selector(updateTextField:)
                     forControlEvents:UIControlEventValueChanged];
    [_dateOfBirthTextBox setInputView:_dateOfBirthDatePicker];

    [_profilePicture.layer setBorderColor:[[UIColor blackColor] CGColor]];
    [_profilePicture.layer setBorderWidth:2.0];

    [_startButton.layer setBorderColor:[[UIColor blackColor] CGColor]];
    [_startButton.layer setBorderWidth:0.5];

    [_callingCardText.layer setBorderColor:[[UIColor blackColor] CGColor]];
    [_callingCardText.layer setBorderWidth:0.5];

    [FBSDKProfile enableUpdatesOnAccessTokenChange:true];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileUpdated:) name:FBSDKProfileDidChangeNotification object:nil];
    self.loginButton.readPermissions = @[@"public_profile", @"user_birthday"];

    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
    }

    NSCalendarUnit unitFlags = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
    NSDate *now = [NSDate date];
    NSCalendar *gregorian = [NSCalendar currentCalendar];
    NSDateComponents *comps = [gregorian components:unitFlags fromDate:now];
    [comps setYear:[comps year] - 100];
    NSDate *hundredYearsAgo = [gregorian dateFromComponents:comps];
    _dateOfBirthDatePicker.minimumDate = hundredYearsAgo;
    _dateOfBirthDatePicker.maximumDate = now;

    [self _updateDisplay];
}

- (void)viewDidAppear:(BOOL)animated {
    if (_waitingForEulaCompletion) {
        _waitingForEulaCompletion = false;
        if ([_socialState hasAcceptedEula]) {
            [self validateForm];
            [self _switchToChatViewHelper];
        }
    }
}

- (IBAction)onDesiredGenderChanged:(id)sender {
    [[SocialState getSocialInstance] persistInterestedInWithSegmentIndex:[_desiredGenderChooser selectedSegmentIndex]];
    [self validateForm];
}

- (IBAction)onOwnerGenderChanged:(id)sender {
    [[SocialState getSocialInstance] persistOwnerGenderWithSegmentIndex:[sender selectedSegmentIndex]];
    [self validateForm];
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
    [self validateForm];
}

- (void)_switchToChatViewHelper {
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

- (void)_switchToChatView {
    if (![[SocialState getSocialInstance] isDataLoaded]) {
        return;
    }

    if (![_socialState hasAcceptedEula]) {
        _waitingForEulaCompletion = true;
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        UIViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"EulaViewController"];
        [self presentViewController:viewController animated:YES completion:nil];
        return;
    }
    
    [self _switchToChatViewHelper];
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
        [_loadingFacebookDetailsIndicator setAlpha:1];
    });
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    // Prevent crashing undo bug – see note below.
    if (range.length + range.location > textView.text.length) {
        return NO;
    }

    int MAX_LENGTH = 300;
    NSUInteger newLength = (textView.text.length - range.length) + text.length;
    if (newLength <= MAX_LENGTH) {
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
        [_loadingFacebookDetailsIndicator setAlpha:0];
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
