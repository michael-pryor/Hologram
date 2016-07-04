//
// Created by Michael Pryor on 02/07/2016.
//

#import "FacebookSharedViewController.h"
#import "Threading.h"
#import "Signal.h"
#import "ViewInteractions.h"


@implementation FacebookSharedViewController {


    __weak IBOutlet UIImageView *_localProfileUiView;
    __weak IBOutlet UITextView *_localCallingTextView;
    __weak IBOutlet UIImageView *_remoteProfileUiView;
    __weak IBOutlet UITextView *_remoteCallingTextView;
    __weak IBOutlet UILabel *_ownerName;
    __weak IBOutlet UILabel *_remoteName;

    __weak IBOutlet UIStackView *_ownerUiView;

    __weak IBOutlet UIView *_localProfileUiViewContainer;
    __weak IBOutlet UIView *_remoteProfileUiViewContainer;

    NSString *_ownerNameString;
    NSString *_ownerCallingCardText;
    UIImage *_ownerProfileImage;

    NSString *_remoteNameString;
    NSString *_remoteCallingCardText;
    UIImage *_remoteProfileImage;

    Signal *_ownerHiddenSignal;
}
- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"CallingCards";

    [_ownerName setText:_ownerNameString];
    [_remoteName setText:_remoteNameString];

    [_localCallingTextView setText:_ownerCallingCardText];
    [_remoteCallingTextView setText:_remoteCallingCardText];

    [_localProfileUiView setImage:_ownerProfileImage];
    [_remoteProfileUiView setImage:_remoteProfileImage];

    _ownerHiddenSignal = [[Signal alloc] initWithFlag:false];

    float borderThickness = 0.5;
    [_localCallingTextView.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_localCallingTextView.layer setBorderWidth: borderThickness];

    [_remoteCallingTextView.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_remoteCallingTextView.layer setBorderWidth: borderThickness];

    [_ownerName.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_ownerName.layer setBorderWidth: borderThickness];

    [_remoteName.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_remoteName.layer setBorderWidth: borderThickness];

    [_remoteProfileUiViewContainer.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_remoteProfileUiViewContainer.layer setBorderWidth: borderThickness];

    [_localProfileUiViewContainer.layer setBorderColor: [[UIColor blackColor] CGColor]];
    [_localProfileUiViewContainer.layer setBorderWidth: borderThickness];
}

// Scroll to top.
- (void)viewDidLayoutSubviews {
    [_localCallingTextView setContentOffset:CGPointZero animated:NO];
    [_remoteCallingTextView setContentOffset:CGPointZero animated:NO];
}

- (IBAction)onScreenTapAndHold:(UILongPressGestureRecognizer*)sender {
    if (sender.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    if ([_ownerHiddenSignal signalAll]) {
        [ViewInteractions fadeOut:_ownerUiView completion:^(BOOL completed) {
            if (!completed) {
                [_ownerHiddenSignal clear];
                return;
            }
            [_ownerUiView setHidden:true];
        } duration:1.0f];
    } else if ([_ownerHiddenSignal clear]) {
        [_ownerUiView setHidden:false];
        [ViewInteractions fadeIn:_ownerUiView completion:^(BOOL completed) {
            if (!completed) {
                [_ownerHiddenSignal signalAll];
                return;
            }
        } duration:1.0f];
    }
}

- (IBAction)onBackButtonPress:(id)sender {
    dispatch_sync_main(^{
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        UIViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"FacebookView"];
        [self.navigationController pushViewController:viewController animated:YES];
    });
}

- (IBAction)onForwardButtonPress:(id)sender {
    dispatch_sync_main(^{
        [self.navigationController popToRootViewControllerAnimated:YES];
    });
}

- (void)setRemoteFullName:(NSString *)remoteFullName remoteCallingText:(NSString *)remoteCallingText remoteProfilePicture:(UIImage *)remoteProfilePicture localFullName:(NSString *)localFullName localCallingText:(NSString *)localCallingText localProfilePicture:(UIImage *)localProfilePicture {
    _ownerNameString = localFullName;
    _remoteNameString = remoteFullName;
    _ownerProfileImage = localProfilePicture;
    _remoteProfileImage = remoteProfilePicture;
    _ownerCallingCardText = localCallingText;
    _remoteCallingCardText = remoteCallingText;
}
@end