//
// Created by Michael Pryor on 02/07/2016.
//

#import "FacebookSharedViewController.h"
#import "Threading.h"
#import "Signal.h"
#import "ViewInteractions.h"
#import "CallingCardViewController.h"


@implementation FacebookSharedViewController {
    __weak IBOutlet UIView *_remoteCallingCard;
    __weak IBOutlet UIView *_localCallingCard;

    CallingCardViewController *_localCallingCardController;
    CallingCardViewController *_remoteCallingCardController;

    void(^_prepareContentsBlock)();

    Signal *_ownerHiddenSignal;
    __weak IBOutlet UIButton *_forwardButton;
    __weak IBOutlet UIButton *_backButton;
    __weak IBOutlet UILabel *_title;
}
- (void)viewDidLoad {
    [super viewDidLoad];

    self.screenName = @"CallingCards";

    _ownerHiddenSignal = [[Signal alloc] initWithFlag:false];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSString *segueName = segue.identifier;
    if ([segueName isEqualToString:@"remoteCallingCard"]) {
        _remoteCallingCardController = [segue destinationViewController];
    } else if ([segueName isEqualToString:@"ownerCallingCard"]) {
        _localCallingCardController = [segue destinationViewController];
    }

    if (_remoteCallingCardController != nil && _localCallingCardController != nil && _prepareContentsBlock != nil) {
        _prepareContentsBlock();
        _prepareContentsBlock = nil;
    }
}

- (IBAction)onScreenTapAndHold:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) {
        return;
    }

    if ([_ownerHiddenSignal signalAll]) {
        [ViewInteractions fadeOut:_localCallingCard completion:^(BOOL completed) {
            if (!completed) {
                [_ownerHiddenSignal clear];
                return;
            }
            [_localCallingCard setHidden:true];
        }                duration:1.0f];
    } else if ([_ownerHiddenSignal clear]) {
        [_localCallingCard setHidden:false];
        [ViewInteractions fadeIn:_localCallingCard completion:^(BOOL completed) {
            if (!completed) {
                [_ownerHiddenSignal signalAll];
                return;
            }
        }               duration:1.0f];
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

- (void)setRemoteFullName:(NSString *)remoteFullName remoteProfilePicture:(UIImage *)remoteProfilePicture remoteCallingText:(NSString *)remoteCallingText localFullName:(NSString *)localFullName localProfilePicture:(UIImage *)localProfilePicture localCallingText:(NSString *)localCallingText {
    void (^theBlock)() = ^{
        // TODO: finish off age and distance.
        [_remoteCallingCardController setName:remoteFullName profilePicture:remoteProfilePicture callingCardText:remoteCallingText age:0 distance:0];
        [_localCallingCardController setName:localFullName profilePicture:localProfilePicture callingCardText:localCallingText age:0 distance:0];
    };
    if (_remoteCallingCard == nil) {
        _prepareContentsBlock = theBlock;
        return;
    }

    dispatch_sync_main(theBlock);
}
@end