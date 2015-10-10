//
//  AlertViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/09/2015.
//
//

#import "AlertViewController.h"
#import "Timer.h"

@implementation AlertViewController {
    IBOutlet UILabel *_alertLongText;
    IBOutlet UILabel *_alertShortText;
    Timer *_timer;
    ADInterstitialAd *_advertDisplay;
    IBOutlet UIView *_advert;
}

- (void)setAlertShortText:(NSString *)shortText longText:(NSString *)longText {
    [_timer reset];

    _alertShortText.text = shortText;
    _alertLongText.text = longText;

    [_alertShortText setNeedsDisplay];
    [_alertLongText setNeedsDisplay];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _timer = [[Timer alloc] initWithFrequencySeconds:2.0 firingInitially:false];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_timer reset];
}

- (Boolean)hideIfVisibleAndReady {
    if (![_timer getState]) {
        return false;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Removing disconnect screen from parent");
        [self willMoveToParentViewController:nil];
        [self removeFromParentViewController];
        [self.view removeFromSuperview];
    });
    return true;
}
@end
