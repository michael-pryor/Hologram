//
//  AlertViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/09/2015.
//
//

#import "AlertViewController.h"
#import "Timer.h"
#import "Threading.h"

@implementation AlertViewController {
    IBOutlet UILabel *_alertShortText;
    Timer *_timerSinceAdvertCreated;
    __weak IBOutlet UIImageView *_localImageView;
}

- (void)setAlertShortText:(NSString *)shortText longText:(NSString *)longText {
    // Alert text has changed, wait at least two seconds more before clearing display.
    [_timerSinceAdvertCreated reset];

    _alertShortText.text = shortText;
    [_alertShortText setNeedsDisplay];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // This frequency represents the maximum amount of time a user will be waiting for the advert to load.
    _timerSinceAdvertCreated = [[Timer alloc] initWithFrequencySeconds:5.0 firingInitially:false];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_timerSinceAdvertCreated reset];
}

- (Boolean)hideIfVisibleAndReady {
    if (![_timerSinceAdvertCreated getState]) {
        return false;
    }

    dispatch_sync_main(^{
        NSLog(@"Removing disconnect screen from parent");
        [self willMoveToParentViewController:nil];
        [self removeFromParentViewController];
        [self.view removeFromSuperview];
    });
    return true;
}

- (void)bannerViewDidLoadAd:(ADBannerView *)banner {
    dispatch_sync_main(^{
        NSLog(@"Banner has loaded, unhiding it");
        [banner setHidden:false];

        // User must wait a minimum of 2 seconds extra while the advert is visible
        // (giving them a chance to see it and click it).
        [_timerSinceAdvertCreated reset];
        [_timerSinceAdvertCreated setSecondsFrequency:2.0];
    });
}

- (void)bannerView:(ADBannerView *)banner didFailToReceiveAdWithError:(NSError *)error {
    dispatch_sync_main(^{
        NSLog(@"Failed to retrieve banner, hiding it; error is: %@", error);
        [banner setHidden:true];

        // Will not wait for banner to be displayed.
        [_timerSinceAdvertCreated setSecondsFrequency:0];
    });
}

- (void)onNewImage:(UIImage *)image {
    [_localImageView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:YES];
}

@end
