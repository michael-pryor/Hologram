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
#import "ConversationEndedViewController.h"

#define MINIMUM_WAIT_TIME 3.0

@implementation AlertViewController {
    IBOutlet UILabel *_alertShortText;
    Timer *_timerSinceAdvertCreated;
    __weak IBOutlet UIImageView *_localImageView;

    __weak IBOutlet UIView *_advertBannerView; // The container which sizes it.
    FBAdView *_advertView; // The actual advert.

    __weak IBOutlet UIButton *_backButton;

    Signal *_localImageViewVisible;

    void(^_moveToFacebookViewControllerFunc)();

    bool _shouldShowAdverts;
    __weak IBOutlet UIView *_conversationEndView;

    ConversationEndedViewController* _conversationEndViewController;

    bool _conversationEndViewControllerVisible;
}

- (void)setAlertShortText:(NSString *)shortText {
    // Alert text has changed, wait at least two seconds more before clearing display.
    [_timerSinceAdvertCreated reset];

    _alertShortText.text = shortText;
    [_alertShortText setNeedsDisplay];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _conversationEndViewController = self.childViewControllers[0];

    // It should be shown at same time as camera, because it sits on top of camera.
    [_backButton setHidden:true];

    _moveToFacebookViewControllerFunc = nil;
    _shouldShowAdverts = false;

    _localImageViewVisible = [[Signal alloc] initWithFlag:false];

    // First images loaded in produce black screen for some reason, so better introduce a delay.


    // This frequency represents the maximum amount of time a user will be waiting for the advert to load.
    _timerSinceAdvertCreated = [[Timer alloc] initWithFrequencySeconds:MINIMUM_WAIT_TIME firingInitially:false];

    _advertView = [[FBAdView alloc] initWithPlacementID:@"458360797698673_526756897525729"
                                                 adSize:kFBAdSizeHeight50Banner
                                     rootViewController:self];

    _advertView.delegate = self;
    [_advertBannerView addSubview:_advertView];

    _advertView.translatesAutoresizingMaskIntoConstraints = NO;

    // Width constraint
    [_advertBannerView addConstraint:[NSLayoutConstraint constraintWithItem:_advertView
                                                                  attribute:NSLayoutAttributeWidth
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:_advertBannerView
                                                                  attribute:NSLayoutAttributeWidth
                                                                 multiplier:1
                                                                   constant:0]];

    // Height constraint, must be 50 because we used adSize = kFBAdSizeHeight50Banner.
    [_advertBannerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[_advertView(==50)]"
                                                                              options:0
                                                                              metrics:nil
                                                                                views:NSDictionaryOfVariableBindings(_advertView)]];

    // Center horizontally
    [_advertBannerView addConstraint:[NSLayoutConstraint constraintWithItem:_advertView
                                                                  attribute:NSLayoutAttributeCenterX
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:_advertBannerView
                                                                  attribute:NSLayoutAttributeCenterX
                                                                 multiplier:1.0
                                                                   constant:0.0]];

    // Center vertically
    [_advertBannerView addConstraint:[NSLayoutConstraint constraintWithItem:_advertView
                                                                  attribute:NSLayoutAttributeBottom
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:_advertBannerView
                                                                  attribute:NSLayoutAttributeBottom
                                                                 multiplier:1.0
                                                                   constant:0.0]];

    [_advertBannerView setAlpha:0.0f];
}

- (NSString *)getScreenName {
    return @"Connecting";
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_timerSinceAdvertCreated setSecondsFrequency:MINIMUM_WAIT_TIME];
    [_timerSinceAdvertCreated reset];

    NSLog(@"Disconnect view controller loaded, unhiding banner advert and setting delegate");
    [_localImageViewVisible clear];
    [_localImageView setAlpha:0.0f];
    [_backButton setHidden:false];

    // Use hidden flag on appear/disappear, in case it impacts decision to display adds.
    if (_shouldShowAdverts) {
        [_advertBannerView setHidden:false];
        [_advertView loadAd];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [_localImageView setAlpha:0.0f];

    // Pause the banner view, stop it loading new adverts.
    NSLog(@"Disconnect view controller hidden, hiding banner advert and removing delegate");
    [_backButton setHidden:true];
    [_advertBannerView setHidden:true];
}

- (void)enableAdverts {
    _shouldShowAdverts = true;
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

- (void)adViewDidLoad:(FBAdView *)adView; {
    dispatch_sync_main(^{
        NSLog(@"Banner has loaded, unhiding it");
        [ViewInteractions fadeIn:_advertBannerView completion:nil duration:0.5f];
    });
}


- (void)adView:(FBAdView *)adView didFailWithError:(NSError *)error; {
    dispatch_sync_main(^{
        NSLog(@"Failed to retrieve banner, hiding it; error is: %@", error);
        [ViewInteractions fadeOut:_advertBannerView completion:nil duration:1.0f];

        // Will not wait for banner to be displayed.
        [_timerSinceAdvertCreated setSecondsFrequency:0];
    });
}

- (void)onNewImage:(UIImage *)image {
    [_localImageView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:YES];
    [self showLocalImageView];
}

- (void)setMoveToFacebookViewControllerFunc:(void (^)())moveToFacebookViewControllerFunc {
    _moveToFacebookViewControllerFunc = moveToFacebookViewControllerFunc;
}

- (IBAction)onGotoFbLogonViewButtonPress:(id)sender {
    if (_moveToFacebookViewControllerFunc != nil) {
        _moveToFacebookViewControllerFunc();
    }
}

- (void)showLocalImageView {
    if (!_conversationEndViewControllerVisible && [_localImageViewVisible signalAll]) {
        [ViewInteractions fadeIn:_localImageView completion:nil duration:0.75f];
    }
}

- (void)setConversationEndedViewVisible:(bool)visible instantly:(bool)instant {
    float fadeDuration = instant ? 0.0f : 0.75f;

    _conversationEndViewControllerVisible = visible;
    if (_conversationEndViewControllerVisible) {
        [_localImageViewVisible clear];
        [ViewInteractions fadeOut:_localImageView completion:^(BOOL finished) {
            if (!finished) {
                return;
            }

            [ViewInteractions fadeIn:_conversationEndView completion:nil duration:fadeDuration];
        }                duration:fadeDuration];
    } else {
        [ViewInteractions fadeOut:_conversationEndView completion:nil duration:fadeDuration];
    }
}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer {
    [_conversationEndViewController setConversationRatingConsumer:consumer];
}
@end

