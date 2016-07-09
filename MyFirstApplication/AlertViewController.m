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

#define MINIMUM_WAIT_TIME 3.0

@implementation AlertViewController {
    IBOutlet UILabel *_alertShortText;
    Timer *_timerSinceAdvertCreated;
    __weak IBOutlet UIImageView *_localImageView;

    __weak IBOutlet UIView *_advertBannerView; // The container which sizes it.
    FBAdView *_advertView; // The actual advert.

    __weak IBOutlet UIButton *_backButton;

    void(^_moveToFacebookViewControllerFunc)();

    bool _shouldShowAdverts;
    __weak IBOutlet UIView *_conversationEndView;

    ConversationEndedViewController *_conversationEndViewController;
    bool _conversationEndViewControllerVisible;
    bool _matchApprovalViewControllerVisible;

    NSArray *_views;

    id <ConversationRatingConsumer> _conversationRatingConsumer;
    uint _ratingTimeoutSeconds;
    uint _matchDecisionTimeoutSeconds;

    NSString *_cachedAlertShortText;

    id <MatchingAnswerDelegate> _matchingAnswerDelegate;

    bool _matchDecisionMade;
    __weak IBOutlet UIView *_matchingView;
    MatchingViewController *_matchingViewController;
}

- (void)setAlertShortText:(NSString *)shortText {
    _cachedAlertShortText = shortText;
    if (_conversationEndViewControllerVisible) {
        return;
    }

    [self doSetAlertShortText:shortText];
}

- (void)doSetAlertShortText:(NSString *)shortText {
    dispatch_sync_main(^{
        // Alert text has changed, wait at least two seconds more before clearing display.
        [_timerSinceAdvertCreated reset];

        _alertShortText.text = shortText;
        [_alertShortText setNeedsDisplay];
    });
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSString *segueName = segue.identifier;
    if ([segueName isEqualToString:@"Rating"]) {
        _conversationEndViewController = [segue destinationViewController];
    } else if ([segueName isEqualToString:@"Matching"]) {
        _matchingViewController = [segue destinationViewController];
        [_matchingViewController setMatchingAnswerDelegate:self];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _views = @[_conversationEndView, _localImageView, _matchingView];
    //[self showView:_localImageView instant:true];

    _matchApprovalViewControllerVisible = false;
    _conversationEndViewControllerVisible = false;
    _conversationRatingConsumer = nil;
    _ratingTimeoutSeconds = 0;
    _conversationEndViewController = self.childViewControllers[0];

    // It should be shown at same time as camera, because it sits on top of camera.
    [_backButton setHidden:true];

    _cachedAlertShortText = nil;
    _moveToFacebookViewControllerFunc = nil;
    _shouldShowAdverts = false;


    _matchDecisionMade = false;

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
    [_localImageView setAlpha:0.0f];
    [_backButton setHidden:false];

    // Use hidden flag on appear/disappear, in case it impacts decision to display adds.
    if (_shouldShowAdverts) {
        [_advertBannerView setHidden:false];
        [_advertView loadAd];
    }

    _matchDecisionMade = false;
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
    if (!_matchDecisionMade || ![_timerSinceAdvertCreated getState]) {
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
}

- (void)setMoveToFacebookViewControllerFunc:(void (^)())moveToFacebookViewControllerFunc {
    _moveToFacebookViewControllerFunc = moveToFacebookViewControllerFunc;
}

- (IBAction)onGotoFbLogonViewButtonPress:(id)sender {
    if (_moveToFacebookViewControllerFunc != nil) {
        _moveToFacebookViewControllerFunc();
    }
}

- (void)showView:(UIView *)viewToShow instant:(bool)instant {
    const float duration = instant ? 0 : 0.75f;

    dispatch_sync_main(^{
        bool shown = false;
        for (UIView *view in _views) {
            if (view == viewToShow) {
                if (viewToShow == _matchingView) {
                    [ViewInteractions fadeOut:viewToShow thenIn:viewToShow duration:duration];
                    shown = true;
                }
                continue;
            }

            if ([view alpha] > 0) {
                if (!shown && [view alpha] == 1) {
                    [ViewInteractions fadeOut:view thenIn:viewToShow duration:duration];
                    shown = true;
                } else {
                    [view setAlpha:0];
                }
            }
        }
        if (!shown) {
            [ViewInteractions fadeIn:viewToShow completion:nil duration:duration];
        }
    });
}

- (void)setConversationEndedViewVisible:(bool)visible instantly:(bool)instant {
    if (_matchApprovalViewControllerVisible || (_conversationEndViewControllerVisible && visible)) {
        return;
    }

    if (visible) {
        [_conversationEndViewController reset];
        [self showView:_conversationEndView instant:instant];
        _conversationEndViewControllerVisible = true;
        [self doSetAlertShortText:@"Please rate your previous conversation\nThis will influence their karma"];
        dispatch_async_main(^{
            [_conversationEndViewController onRatingsCompleted];
        }, _ratingTimeoutSeconds * 1000);

    } else {
        [self showView:_localImageView instant:instant];
        _conversationEndViewControllerVisible = false;
        [self doSetAlertShortText:_cachedAlertShortText];
    }

}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate ratingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeoutSeconds:(uint)matchDecisionTimeoutSeconds {
    _conversationRatingConsumer = consumer;
    _matchDecisionTimeoutSeconds = matchDecisionTimeoutSeconds;
    _ratingTimeoutSeconds = ratingTimeoutSeconds;
    [_conversationEndViewController setConversationRatingConsumer:self];
    [_matchingViewController setMatchingDecisionTimeoutSeconds:matchDecisionTimeoutSeconds];
    _matchingAnswerDelegate = matchingAnswerDelegate;
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    [self setConversationEndedViewVisible:false instantly:false];
    [_conversationRatingConsumer onConversationRating:conversationRating];
}

- (void)onMatchAcceptAnswer {
    _matchDecisionMade = true;
    [_matchingAnswerDelegate onMatchAcceptAnswer];
    [self onMatchingFinished];
}

- (void)onMatchingFinished {
    _matchApprovalViewControllerVisible = false;
    [self showView:_localImageView instant:false];
}

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance {
    [_matchingViewController setName:name profilePicture:profilePicture callingCardText:callingCardText age:age distance:distance];
    [self onMatchingStarted];
}

- (void)onMatchingStarted {
    _matchApprovalViewControllerVisible = true;
    [self showView:_matchingView instant:false];
}

- (void)onMatchRejectAnswer {
    [_matchingAnswerDelegate onMatchRejectAnswer];
    [self onMatchingFinished];
}

- (void)onMatchBlocked {
    [_matchingAnswerDelegate onMatchBlocked];
    [self onMatchingFinished];
}

- (void)onTimedOut {
    [self onMatchingFinished];
}

@end

