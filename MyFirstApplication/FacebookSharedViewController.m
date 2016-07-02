//
// Created by Michael Pryor on 02/07/2016.
//

#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import "FacebookSharedViewController.h"
#import "Threading.h"


@implementation FacebookSharedViewController {

    __weak IBOutlet FBSDKProfilePictureView *_ownerProfilePicture;
    __weak IBOutlet FBSDKProfilePictureView *_remoteProfilePicture;
    __weak IBOutlet UILabel *_ownerName;
    __weak IBOutlet UILabel *_remoteName;

    NSString* _ownerNameString;
    NSString *_ownerFacebookId;

    NSString *_remoteNameString;
    NSString *_remoteFacebookId;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [_ownerName setText:_ownerNameString];
    [_remoteName setText:_remoteNameString];

    [_ownerProfilePicture setProfileID:_ownerFacebookId];
    [_remoteProfilePicture setProfileID:_remoteFacebookId];
}

- (void)setRemoteFacebookId:(NSString *)remoteFacebookId remoteProfileUrl:(NSString *)remoteProfileUrl remoteFullName:(NSString *)remoteFullName localFacebookId:(NSString *)localFacebookId localFullName:(NSString *)localFullName {
    _ownerNameString = localFullName;
    _ownerFacebookId = localFacebookId;
    _remoteNameString = remoteFullName;
    _remoteFacebookId = remoteFacebookId;
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
- (IBAction)onGotoFacebookPageButtonPress:(id)sender {
    NSString *link = [NSString stringWithFormat:@"fb://profile?app_scoped_user_id=%@", _remoteFacebookId];
    NSURL *facebookURL = [NSURL URLWithString:link];
    if ([[UIApplication sharedApplication] canOpenURL:facebookURL]) {
        [[UIApplication sharedApplication] openURL:facebookURL];
    }
}
@end