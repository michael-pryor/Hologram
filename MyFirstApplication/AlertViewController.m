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
#import "ViewInteractions.h"
#import <Google/Analytics.h>

@implementation AlertViewController {
    IBOutlet UILabel *_alertShortText;
    Timer *_timerSinceAdvertCreated;
    __weak IBOutlet UIImageView *_localImageView;
    __weak IBOutlet ADBannerView *_bannerView;
    Signal *_localImageViewVisible;
    volatile Timer *_localImageFadeInDelayTimer;
}

- (void)setAlertShortText:(NSString *)shortText longText:(NSString *)longText {
    // Alert text has changed, wait at least two seconds more before clearing display.
    [_timerSinceAdvertCreated reset];

    _alertShortText.text = shortText;
    [_alertShortText setNeedsDisplay];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _localImageViewVisible = [[Signal alloc] initWithFlag:false];

    // First images loaded in produce black screen for some reason, so better introduce a delay.


    // This frequency represents the maximum amount of time a user will be waiting for the advert to load.
    _timerSinceAdvertCreated = [[Timer alloc] initWithFrequencySeconds:5.0 firingInitially:false];

    [_bannerView setAlpha:0.0f];
    [_localImageView setAlpha:0.0f];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_timerSinceAdvertCreated reset];
    [_localImageViewVisible clear];
    [_localImageView setAlpha:0.0f];
    _localImageFadeInDelayTimer = [[Timer alloc] initWithFrequencySeconds:1 firingInitially:false];

    NSLog(@"Alert view loaded, unhiding banner advert and setting delegate");
    _bannerView.delegate = self;
    [_bannerView setHidden:false];
    
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker set:kGAIScreenName value:@"ConnectingScreen"];
    [tracker send:[[GAIDictionaryBuilder createScreenView] build]];
}

- (void)viewDidDisappear:(BOOL)animated {
    dispatch_sync_main(^{
        [_localImageView setAlpha:0.0f];
        _localImageFadeInDelayTimer = nil;

        // Pause the banner view, stop it loading new adverts.
        NSLog(@"Alert view hidden, hiding banner advert and removing delegate");
        _bannerView.delegate = nil;
        [_bannerView setHidden:true];
    });
}

- (void)hideNow {
    dispatch_sync_main(^{
        NSLog(@"Removing disconnect screen from parent");
        [self willMoveToParentViewController:nil];
        [self removeFromParentViewController];
        [self.view removeFromSuperview];
    });
}

- (Boolean)hideIfVisibleAndReady {
    if (![_timerSinceAdvertCreated getState]) {
        return false;
    }

    [self hideNow];
    return true;
}

- (void)bannerViewDidLoadAd:(ADBannerView *)banner {
    dispatch_sync_main(^{
        NSLog(@"Banner has loaded, unhiding it");
        [ViewInteractions fadeIn:_bannerView completion:nil duration:1.0f];

        // User must wait a minimum of 2 seconds extra while the advert is visible
        // (giving them a chance to see it and click it).
        [_timerSinceAdvertCreated reset];
        [_timerSinceAdvertCreated setSecondsFrequency:2.0];
    });
}

- (void)bannerView:(ADBannerView *)banner didFailToReceiveAdWithError:(NSError *)error {
    dispatch_sync_main(^{
        NSLog(@"Failed to retrieve banner, hiding it; error is: %@", error);
        [ViewInteractions fadeOut:_bannerView completion:nil duration:1.0f];

        // Will not wait for banner to be displayed.
        [_timerSinceAdvertCreated setSecondsFrequency:0];
    });
}

- (void)onNewImage:(UIImage *)image {
    [_localImageView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:YES];

    if (_localImageFadeInDelayTimer != nil && [_localImageFadeInDelayTimer getState] && [_localImageViewVisible signalAll]) {
        [ViewInteractions fadeIn:_localImageView completion:nil duration:1.0f];
    }
}

@end

