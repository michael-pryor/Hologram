//
// Created by Michael Pryor on 04/07/2016.
//

#import "EndUserLicenseAgreementViewController.h"
#import "Threading.h"
#import "SocialState.h"


@implementation EndUserLicenseAgreementViewController {
    __weak IBOutlet UITextView *_eulaTextView;
}

- (void)viewDidLoad {
    [_eulaTextView.layer setBorderColor:[[UIColor blackColor] CGColor]];
    [_eulaTextView.layer setBorderWidth:0.5];

    self.screenName = @"EULA";
}

- (IBAction)onAcceptButtonPress:(id)sender {
    [[SocialState getSocialInstance] persistHasAcceptedEula];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (IBAction)onCancelButtonPress:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Scroll to top on UITextViews.
- (void)viewDidLayoutSubviews {
    [_eulaTextView setContentOffset:CGPointZero animated:NO];
}
@end