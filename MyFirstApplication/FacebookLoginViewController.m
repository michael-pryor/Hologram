//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import <MultiSelectSegmentedControl/MultiSelectSegmentedControl.h>
#import "FacebookLoginViewController.h"
#import "Threading.h"
#import "DobParsing.h"
#import "Notifications.h"

#define kHotNotification @"hotNotification"

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
    NSArray *_warningItems;

    bool _waitingForEulaCompletion;
    __weak IBOutlet UISwitch *_hotEnableSwitch;
    __weak IBOutlet MultiSelectSegmentedControl *_hotDaySelector;
    __weak IBOutlet UIStackView *_hotDayStack;
    __weak IBOutlet UILabel *_notificationPermissionsRequestWarning;
    __weak IBOutlet UILabel *_hotDescription;
    Notifications *_notifications;
}

- (void)cancelEditingTextBoxes {
    [self.view endEditing:YES];
    [self saveTextBoxes];
}

- (IBAction)onReviewButtonPress:(id)sender {
    [[UIApplication sharedApplication] openURL:[[NSURL alloc] initWithString:@"itms-apps://itunes.apple.com/us/app/hologram/id1065376316?ls=1&mt=8"]];
}

- (IBAction)onProfilePictureTap:(id)sender {
    [self cancelEditingTextBoxes];

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

- (IBAction)onHotEnabledPress:(id)sender {
    [self cancelEditingTextBoxes];

    bool enabled = [_hotEnableSwitch isOn];
    [_socialState persistIsHotNotificationEnabled:enabled];
    [self setHotEnableSwitch:enabled];
}

- (void)multiSelect:(MultiSelectSegmentedControl *)multiSelectSegmentedControl didChangeValue:(BOOL)selected atIndex:(NSUInteger)index {
    [self cancelEditingTextBoxes];

    NSMutableArray *indexesArray = [[NSMutableArray alloc] init];
    [[multiSelectSegmentedControl selectedSegmentIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexesArray addObject:@(idx)];
    }];

    [_socialState persistHotNotificationDays:indexesArray];
    [self updateNotifications:multiSelectSegmentedControl];
}

- (void)updateNotifications:(MultiSelectSegmentedControl *)control {
    [_notifications cancelNotificationsWithId:kHotNotification];
    if (![_hotEnableSwitch isOn]) {
        return;
    }

    NSMutableString *daysHumanReadable = [[NSMutableString alloc] init];
    NSMutableArray *daysIntegers = [[NSMutableArray alloc] init];
    [[control selectedSegmentIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        // Sunday = 1, Monday = 2, Tuesday = 3, Wednesday = 4, Thursday = 5, Friday = 6, Saturday = 7
        uint dateFormattedDay = (idx + 2) % 7;
        NSDate *now = [NSDate date];
        NSCalendar *calendar = [NSCalendar currentCalendar];
        [calendar setTimeZone:[NSTimeZone localTimeZone]];
        NSDateComponents *components = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfYear | NSCalendarUnitWeekday fromDate:now];
        components.weekday = dateFormattedDay;
        components.hour = 20;

        [daysIntegers addObject:@(dateFormattedDay)];

        NSDate *fireDate = [calendar dateFromComponents:components];

        // Ensure date is in the future, by adding one week, if it is in the past.
        if ([fireDate earlierDate:now] == fireDate) {
            NSDateComponents *dateComponents = [[NSDateComponents alloc] init];
            [dateComponents setWeekOfYear:1];
            fireDate = [calendar dateByAddingComponents:dateComponents toDate:fireDate options:0];
        }

        UILocalNotification *hotNotification = [_notifications getLocalNotificationWithId:kHotNotification];
        [hotNotification setRepeatInterval:NSCalendarUnitWeekOfYear]; // repeat every week.
        [hotNotification setFireDate:fireDate];

        hotNotification.alertBody = @"🔥 Today's hot spot in your region has started, join in now!";
        hotNotification.alertTitle = @"Hologram Hot Spot";

        hotNotification.soundName = UILocalNotificationDefaultSoundName;
        hotNotification.applicationIconBadgeNumber = 1;
        [[UIApplication sharedApplication] scheduleLocalNotification:hotNotification];

        NSLog(@"Scheduled weekly repeated hot notification to take place on: %@ (UTC)", fireDate);
    }];

    if ([daysIntegers count] == 7) {
        dispatch_sync_main(^{
            [_hotDescription setText:@"\U0001F525 You will receive hot spot notifications every day"];
        });
        return;
    } else if ([daysIntegers count] == 0) {
        dispatch_sync_main(^{
            [_hotDescription setText:@"\U0001F525 You will not receive hot spot notifications"];
        });
        return;
    } else {
        int count = 0;
        for (NSNumber *num in daysIntegers) {
            int numI = [num unsignedIntValue];
            switch (numI) {
                case 1:
                    [daysHumanReadable appendString:@"Sunday"];
                    break;

                case 2:
                    [daysHumanReadable appendString:@"Monday"];
                    break;

                case 3:
                    [daysHumanReadable appendString:@"Tuesday"];
                    break;

                case 4:
                    [daysHumanReadable appendString:@"Wednesday"];
                    break;

                case 5:
                    [daysHumanReadable appendString:@"Thursday"];
                    break;

                case 6:
                    [daysHumanReadable appendString:@"Friday"];
                    break;

                case 0:
                    [daysHumanReadable appendString:@"Saturday"];
                    break;

                default:
                    [daysHumanReadable appendString:@"Unknown day!"];
                    break;
            }
            count++;

            if (count == ((int) [daysIntegers count]) - 1) {
                [daysHumanReadable appendString:@" and "];
            }
            if (count <= ((int) [daysIntegers count]) - 2) {
                [daysHumanReadable appendString:@", "];
            }
        }
    }

    [daysHumanReadable insertString:@"\U0001F525 You will receive hot spot notifications on " atIndex:0];
    dispatch_sync_main(^{
        [_hotDescription setText:daysHumanReadable];
    });
}


- (bool)handleValidationItem:(UIView *)item problemFlag:(bool)problemFlag {
    if (problemFlag) {
        [_startButton setEnabled:false];
        [_startButton setAlpha:0.2];

        [item setHidden:false];
        for (UIView *otherItem in _warningItems) {
            if (otherItem == item) {
                continue;
            }
            [otherItem setHidden:true];
        }
        return true;
    }

    [item setHidden:true];
    return false;
}

- (void)validateForm {
    dispatch_sync_main(^{
        if ([self handleValidationItem:_warningName problemFlag:[[_fullNameTextBox text] length] == 0]) {
            return;
        }

        if ([self handleValidationItem:_warningDateOfBirth problemFlag:[[_dateOfBirthTextBox text] length] == 0]) {
            return;
        }

        if ([self handleValidationItem:_warningAgeRestriction problemFlag:[_socialState age] < MINIMUM_AGE]) {
            return;
        }

        if ([self handleValidationItem:_warningGender problemFlag:[_ownerGenderChooser selectedSegmentIndex] == UISegmentedControlNoSegment]) {
            return;
        }

        if ([self handleValidationItem:_warningCallingCardPicture problemFlag:[_socialState profilePictureImage] == nil]) {
            return;
        }

        [_startButton setEnabled:true];
        [_startButton setAlpha:1];
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
}

- (IBAction)onViewControllerTap:(id)sender {
    [self cancelEditingTextBoxes];
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

    _warningItems = @[_warningAgeRestriction, _warningCallingCardPicture, _warningDateOfBirth, _warningGender, _warningName];

    [_hotDaySelector setDelegate:self];
    [_hotDaySelector setHideSeparatorBetweenSelectedSegments:YES];

    _notifications = [Notifications getNotificationsInstance];

    _waitingForEulaCompletion = false;
    [_loadingFacebookDetailsIndicator setAlpha:0];

    _socialState = [SocialState getSocialInstance];
    [_socialState registerNotifier:self];

    [self initializeDatePicker];

    [_profilePicture.layer setBorderColor:[[UIColor blackColor] CGColor]];
    [_profilePicture.layer setBorderWidth:2.0];

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

    // No need to put this inside updateDisplay, since it will only change from user changing, not from facebook load.
    NSArray *hotDaySelection = [_socialState hotNotificationDays];
    if (hotDaySelection != nil) {
        NSMutableIndexSet *selectedSegmentIndexes = [[NSMutableIndexSet alloc] init];
        for (NSNumber *obj in hotDaySelection) {
            uint objNum = [obj unsignedIntValue];
            [selectedSegmentIndexes addIndex:objNum];
        }

        [_hotDaySelector setSelectedSegmentIndexes:selectedSegmentIndexes];
    } else {
        [_hotDaySelector selectAllSegments:YES];
    }

    bool isHotEnabled = [_socialState isHotNotificationEnabled];
    [self setHotEnableSwitch:isHotEnabled];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillRetakeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)initializeDatePicker {
    _dateOfBirthDatePicker = [[UIDatePicker alloc] init]; // needs to be retained.
    _dateOfBirthDatePicker.datePickerMode = UIDatePickerModeDate;
    [_dateOfBirthTextBox setInputView:_dateOfBirthDatePicker];
    [_dateOfBirthDatePicker addTarget:self action:@selector(updateTextField:)
                     forControlEvents:UIControlEventValueChanged];
    [_dateOfBirthTextBox setInputView:_dateOfBirthDatePicker];
}

- (void)appWillRetakeActive:(id)appWillRetakeActive {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
}

- (void)setHotEnableSwitch:(bool)on {
    [_hotEnableSwitch setOn:on];

    if (on) {
        [_notifications enableNotifications];
    }
    [_notificationPermissionsRequestWarning setHidden:[_notifications notificationsEnabled]];
    [_hotDayStack setHidden:!on];

    [self updateNotifications:_hotDaySelector];
}

- (void)enableScreenDim {
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [self enableScreenDim];
    if (_waitingForEulaCompletion) {
        _waitingForEulaCompletion = false;
        if ([_socialState hasAcceptedEula]) {
            [self validateForm];
            [self _switchToChatViewHelper];
        }
    }
}

- (IBAction)onDesiredGenderChanged:(id)sender {
    [self cancelEditingTextBoxes];

    [[SocialState getSocialInstance] persistInterestedInWithSegmentIndex:(int) [_desiredGenderChooser selectedSegmentIndex]];
    [self validateForm];
}

- (IBAction)onOwnerGenderChanged:(id)sender {
    [self cancelEditingTextBoxes];

    [[SocialState getSocialInstance] persistOwnerGenderWithSegmentIndex:(int) [sender selectedSegmentIndex]];
    [self validateForm];
}

- (void)_updateDisplay {
    dispatch_sync_main(^{
        NSDate *dobObject = [_socialState dobObject];
        if (dobObject != nil) {
            // Reinitializing here prevents a crash.
            // The crash we saw was: load from FB, adjust date manually, load from FB, adjust date manually (crash here).
            [self initializeDatePicker];

            [_dateOfBirthDatePicker setDate:dobObject];
            [_dateOfBirthTextBox setText:[_socialState dobString]];
        }

        _desiredGenderChooser.selectedSegmentIndex = [_socialState interestedInSegmentIndex];
        _ownerGenderChooser.selectedSegmentIndex = [_socialState genderSegmentIndex];

        _fullNameTextBox.text = [_socialState humanFullName];

        [_profilePicture setImage:[_socialState profilePictureImage]];

        [_callingCardText setText:[_socialState callingCardText]];
        [self validateForm];
    });
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
    [self cancelEditingTextBoxes];
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
    // We may get updates, even if user hasn't recently logged in, i.e. we can get multiple (some may be hours or days later).
    if (![_socialState isLoadingFacebookData]) {
        NSLog(@"Facebook profile updated notification received, IGNORING!!");
        return;
    }

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
        if (newLength <= 50) {
            return YES;
        }
        return NO;
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
    [self cancelEditingTextBoxes];

    if ([result isCancelled]) {
        NSLog(@"User cancelled login attempt");
        [_socialState persistIsLoadingFacebookData:false];
    } else {
        NSLog(@"Logged in successfully, retrieving credentials...");
        [_socialState persistIsLoadingFacebookData:true];
    }
}

- (void)loginButtonDidLogOut:(FBSDKLoginButton *)loginButton {
    NSLog(@"Logged out successfully");
    [_socialState persistIsLoadingFacebookData:false];
}

- (IBAction)onGuideButtonPress:(id)sender {
    [self cancelEditingTextBoxes];

    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    UIViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"HelpViewController"];
    [self presentViewController:viewController animated:YES completion:nil];
}
@end
