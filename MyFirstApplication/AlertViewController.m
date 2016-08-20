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
#import "ViewTransitions.h"
#import "JoiningViewController.h"
#import "MediaController.h"

@implementation AlertViewController {
    // Base view, describing state of app and connection.
    __weak IBOutlet UIImageView *_localImageView;
    __weak IBOutlet UIView *_localImageViewParent;
    IBOutlet UILabel *_alertShortText;
    __weak IBOutlet UILabel *_alertShortTextHigher;
    __weak IBOutlet UIButton *_backButton;
    __weak IBOutlet UIButton *_forwardButton;
    id <MediaOperator> _mediaOperator;
    bool _movingToFacebook;

    NSString *_cachedAlertText;

    // Advert.
    __weak IBOutlet UIView *_advertBannerView; // The container which sizes it.
    FBAdView *_advertView; // The actual advert.
    bool _shouldShowAdverts;
    int _actionIterationAdvertSchedule;
    bool _isBannerAdvertLoaded;

    // Rating previous conversation..
    __weak IBOutlet UIView *_conversationEndView;
    ConversationEndedViewController *_conversationEndViewController;
    id <ConversationRatingConsumer> _conversationRatingConsumer;
    uint _ratingTimeoutSeconds;
    Signal *_waitingForRating;
    Timer *_ratingStartedAt;


    // Matching i.e. viewing cards.
    __weak IBOutlet UIView *_matchingView;
    MatchingViewController *_matchingViewController;
    id <MatchingAnswerDelegate> _matchingAnswerDelegate;

    // Accepted a match, waiting for other side to accept too.
    __weak IBOutlet UIView *_joiningConversationView;
    JoiningViewController *_joiningConversationViewController;

    // All views, we only have one visible at a time.
    SingleViewCollection *_viewCollection;

    bool _isSkipButtonRequired;
}

- (void)reset {
    [_alertShortText setText:@"Initializing"];
}

- (bool)isViewCurrent:(UIView *)view {
    return [_viewCollection isViewCurrent:view];
}

- (bool)isInConversationEndedView {
    return [self isViewCurrent:_conversationEndView];
}

- (bool)isInMatchApprovalView {
    return [self isViewCurrent:_matchingView];
}

- (bool)isWaitingForMatchToJoin {
    return [self isViewCurrent:_joiningConversationView];
}

- (bool)shouldAdvertBeVisible:(UIView*)view {
    return view == _localImageViewParent && _isBannerAdvertLoaded;
}

- (bool)shouldVideoBeOnView:(UIView *)view {
    // We need video in the joining stage so that we send some packets
    // and remove each other's disconnect view.
    return (view == _localImageViewParent ||
            view == _joiningConversationView) && !_movingToFacebook;
}

- (bool)shouldVideoBeOn {
    return [self shouldVideoBeOnView:[_viewCollection getCurrentlyDisplayedView]];
}

- (void)signalMovingToFacebookController {
    _movingToFacebook = true;
    [self hideViewsQuickly:true];
}

- (void)setGenericInformationText:(NSString *)shortText skipButtonEnabled:(bool)skipButtonEnabled {
    dispatch_sync_main(^{
        _cachedAlertText = shortText;
        _isSkipButtonRequired = skipButtonEnabled;
    });
}

- (void)setViewRelevantInformationText:(NSString *)text {
    dispatch_sync_main(^{
        _alertShortTextHigher.text = text;
        [_alertShortTextHigher setNeedsDisplay];
    });
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSString *segueName = segue.identifier;
    if ([segueName isEqualToString:@"Rating"]) {
        _conversationEndViewController = [segue destinationViewController];
    } else if ([segueName isEqualToString:@"Matching"]) {
        _matchingViewController = [segue destinationViewController];
        [_matchingViewController setMatchingAnswerDelegate:self];
    } else if ([segueName isEqualToString:@"JoiningConversation"]) {
        _joiningConversationViewController = [segue destinationViewController];
        [_joiningConversationViewController setTimeoutDelegate:self];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSLog(@"!!!!!!LOAD!!!!!!");
    _actionIterationAdvertSchedule = false;
    _actionIterationAdvertSchedule = 0;
    _isBannerAdvertLoaded = false;

    _waitingForRating = [[Signal alloc] initWithFlag:false];

    for (UIView *view in @[_conversationEndView, _matchingView, _joiningConversationView, _localImageViewParent, _alertShortTextHigher,
            _forwardButton, _backButton]) {
        [view setAlpha:0];
    }

    _viewCollection = [[SingleViewCollection alloc] initWithDuration:0.5f viewChangeNotifier:self];
    [_viewCollection registerNoFadeView:_localImageViewParent];
    _conversationRatingConsumer = nil;
    _ratingStartedAt = nil;
    _ratingTimeoutSeconds = 0;
    _movingToFacebook = false;
    _shouldShowAdverts = false;

    // Start off initializing, no skip button.
    _isSkipButtonRequired = false;
    [_forwardButton setHidden:true];

    _cachedAlertText = nil;

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

    NSLog(@"!!!!!!APPEAR!!!!!!");

    _movingToFacebook = false;
    if ([self shouldVideoBeOn]) {
        [_mediaOperator startVideo];
    }

    [_mediaOperator stopAudio];

    NSLog(@"Disconnect view controller loaded, unhiding banner advert and setting delegate");

    // Use hidden flag on appear/disappear, in case it impacts decision to display adds.
    if (_shouldShowAdverts) {
        [_advertView loadAd];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    NSLog(@"!!!!!!DISAPPEAR!!!!!!");

    // Pause the banner view, stop it loading new adverts.
    NSLog(@"Disconnect view controller hidden, hiding banner advert and removing delegate");

    // Ensures state is reset, and starts the video.
    // Which definitely will be needed if hiding the view controller.
    if (!_movingToFacebook) {
        [_mediaOperator startAudio];
        [_mediaOperator startVideo];
    }

    [_joiningConversationViewController stop];
}

- (void)enableAdverts {
    _shouldShowAdverts = true;
}

- (void)hideNow {
    NSLog(@"!!!!!!HIDING!!!!!!");
    dispatch_sync_main(^{
        NSLog(@"Removing disconnect screen from parent");
        [ViewTransitions hideChildViewController:self];
    });
}

- (Boolean)hideIfVisibleAndReady {
    [self hideNow];
    return true;
}

- (void)adViewDidLoad:(FBAdView *)adView; {
    dispatch_sync_main(^{
        // On next screen refresh, we'l show the advert.
        _isBannerAdvertLoaded = true;
        NSLog(@"Banner has loaded, unhiding it");
    });
}


- (void)adView:(FBAdView *)adView didFailWithError:(NSError *)error; {
    dispatch_sync_main(^{
        NSLog(@"Failed to retrieve banner, hiding it; error is: %@", error);
        _isBannerAdvertLoaded = false;
        [ViewInteractions fadeOut:_advertBannerView completion:nil duration:1.0f];
    });
}

- (void)onNewImage:(UIImage *)image {
    [_localImageView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:YES];
}

- (void)hideViewsQuickly:(bool)showQuickly {
    [self showView:_localImageViewParent showQuickly:showQuickly];
}

- (void)showView:(UIView *)viewToShow showQuickly:(bool)showQuickly {
    if (viewToShow == _localImageViewParent && !showQuickly) {
        [_viewCollection displayView:viewToShow ifNoChangeForMilliseconds:1000 meta:_cachedAlertText];
        return;
    }

    if (viewToShow == _matchingView) {
        _actionIterationAdvertSchedule++;
        if (_actionIterationAdvertSchedule > 3) {
            _actionIterationAdvertSchedule = 0;

            if (_shouldShowAdverts && _isBannerAdvertLoaded) {
                dispatch_async_main(^{
                    [_viewCollection displayView:viewToShow meta:_cachedAlertText];
                }, 3000);
                return;
            }
        }
    }

    [_viewCollection displayView:viewToShow meta:_cachedAlertText];
    _cachedAlertText = nil;
}

- (void)setConversationEndedViewVisible:(bool)visible showQuickly:(bool)showQuickly {
    if ([self isInMatchApprovalView] || ([self isInConversationEndedView] && visible)) {
        return;
    }

    if (visible && [_waitingForRating signalAll]) {
        [_conversationEndViewController reset];
        [self showView:_conversationEndView showQuickly:showQuickly];
        [self setViewRelevantInformationText:@"Please rate your previous conversation\nThis will influence their karma"];
        _ratingStartedAt = [[Timer alloc] init];
        __block Timer *comparisonTimer = [[Timer alloc] initFromTimer:_ratingStartedAt];
        dispatch_async_main(^{
            if ([comparisonTimer getTimerEpoch] != [_ratingStartedAt getTimerEpoch]) {
                return;
            }

            [_conversationEndViewController onRatingsCompleted];
            [_waitingForRating clear];
        }, _ratingTimeoutSeconds * 1000);
    } else if (![_waitingForRating isSignaled]) {
        [self hideViewsQuickly:showQuickly];
    }

}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate mediaOperator:(id <MediaOperator>)videoOperator {
    _conversationRatingConsumer = consumer;
    [_conversationEndViewController setConversationRatingConsumer:self];
    _matchingAnswerDelegate = matchingAnswerDelegate;
    _mediaOperator = videoOperator;
}

- (void)setRatingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeoutSeconds:(uint)matchDecisionTimeoutSeconds {
    _ratingTimeoutSeconds = ratingTimeoutSeconds;
    [_matchingViewController setMatchingDecisionTimeoutSeconds:matchDecisionTimeoutSeconds];
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    [_conversationRatingConsumer onConversationRating:conversationRating];
    [_waitingForRating clear];

    // It felt sloppy if not moving quickly out of this screen.
    [self setConversationEndedViewVisible:false showQuickly:true];
}

- (void)onMatchAcceptAnswer {
    [_matchingAnswerDelegate onMatchAcceptAnswer];
    [self setViewRelevantInformationText:@"Waiting for your match to accept too"];
    [_joiningConversationViewController consumeRemainingTimer:[_matchingViewController cloneTimer]];
    [self showView:_joiningConversationView showQuickly:false];
}

- (void)onMatchingFinishedHideViews:(bool)quicklyHideViews {
    [self hideViewsQuickly:quicklyHideViews];
}

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance karma:(uint)karma maxKarma:(uint)maxKarma isReconnectingClient:(bool)isReconnectingClient{
    // If user we are waiting for reconnects, we receive their information again, but if it is the same user, we just want to carry on waiting,
    // without showing the card again.
    if (isReconnectingClient && [self isWaitingForMatchToJoin] && ![_matchingViewController isChangeInName:name profilePicture:profilePicture callingCardText:callingCardText age:age]) {
        NSLog(@"Was waiting for match to join but received duplicate profile while waiting for reconnect; not displaying profile");
        return;
    }

    [_matchingViewController setName:name profilePicture:profilePicture callingCardText:callingCardText age:age distance:distance karma:karma maxKarma:maxKarma isReconnectingClient:isReconnectingClient];
    [self onMatchingStarted];
}

- (void)onMatchingStarted {
    [self showView:_matchingView showQuickly:false];
}

- (bool)onMatchRejectAnswer {
    if ([_matchingAnswerDelegate onMatchRejectAnswer]) {
        [self onMatchingFinishedHideViews:false];
        return true;
    }

    return false;
}

- (void)onMatchBlocked {
    [_matchingAnswerDelegate onMatchBlocked];

    // Want to quickly get rid of card, since user blocked/reported them.
    [self onMatchingFinishedHideViews:true];
}

- (void)onTimedOut {
    [self onMatchingFinishedHideViews:false];
}

- (void)onBackToSocialRequest {
    [_matchingAnswerDelegate onBackToSocialRequest];
}

- (IBAction)onGotoFbLogonViewButtonPress:(id)sender {
    dispatch_sync_main(^{
        [_backButton setAlpha:ALPHA_BUTTON_PRESSED];
    });
    [self onBackToSocialRequest];
}


- (IBAction)onForwardButtonPress:(id)sender {
    dispatch_sync_main(^{
        [_forwardButton setAlpha:ALPHA_BUTTON_PRESSED];
    });
    // Just send the skip request, don't change what view we're in. Because this could easily
    // trigger a rating request, we don't want to interupt that in any way.
    [_matchingAnswerDelegate onMatchRejectAnswer];
}


- (void)onStartedFadingOut:(UIView *)view duration:(float)duration alpha:(float)alpha {
    if ([self isAssociatedWithAlertShortTextHigher:view]) {
        [self fadeOutView:_alertShortTextHigher duration:duration alpha:alpha];
    }

    if ([self doesViewUseButtons:view]) {
        [self fadeOutView:_forwardButton duration:duration alpha:alpha];
        [self fadeOutView:_backButton duration:duration alpha:alpha];
    }

    if (![self shouldAdvertBeVisible:view] || alpha != 1.0f) {
        [self fadeOutView:_advertBannerView duration:duration alpha:0];
    }

    [self fadeOutView:_alertShortText duration:duration alpha:0.4];
}

- (void)onFinishedFadingOut:(UIView *)view duration:(float)duration alpha:(float)alpha {
    if ([self shouldVideoBeOnView:view] && alpha != 1.0f) {
        [_mediaOperator stopVideo];
    }

    // Rectify any temporary change we made.
    if (!_isSkipButtonRequired) {
        [_forwardButton setHidden:true];
    }
}

- (void)onStartedFadingIn:(UIView *)view duration:(float)duration meta:(id)meta {
    if ([self shouldVideoBeOnView:view]) {
        [_mediaOperator startVideo];
    }

    if ([self shouldAdvertBeVisible:view]) {
        [self fadeInView:_advertBannerView duration:duration alpha:1.0];
    }

    if ([self isAssociatedWithAlertShortTextHigher:view]) {
        [self fadeInView:_alertShortTextHigher duration:duration alpha:1.0];
    }

    if ([self doesViewUseButtons:view]) {
        [self fadeInView:_forwardButton duration:duration alpha:ALPHA_BUTTON_IMAGE_READY];
        [self fadeInView:_backButton duration:duration alpha:ALPHA_BUTTON_IMAGE_READY];
    }

    NSString *alertText = meta;
    if (alertText != nil) {
        [_alertShortText setText:alertText];
    }

    // Never have a situation where there would be no text to show...
    [self fadeInView:_alertShortText duration:duration alpha:1.0f];
}

- (void)fadeInView:(UIView *)view duration:(float)duration alpha:(float)alpha {
    [ViewInteractions fadeIn:view completion:^(BOOL completion) {
        if (!completion) {
            // Do nothing, do not complete the animation, it's probably
            // been overriden by another opposite animation.
        }
    }               duration:duration toAlpha:alpha];
}

- (void)fadeOutView:(UIView *)view duration:(float)duration alpha:(float)alpha{
    [ViewInteractions fadeOut:view completion:^(BOOL completion) {
        if (!completion) {
            // Do nothing, do not complete the animation, it's probably
            // been overriden by another opposite animation.
        }
    }                duration:duration toAlpha:alpha];
}

- (bool)isAssociatedWithAlertShortTextHigher:(UIView *)view {
    return view == _conversationEndView || view == _joiningConversationView;
}

- (bool)doesViewUseButtons:(UIView *)view {
    return view == _localImageViewParent || view == _joiningConversationView;
}

- (bool)doesViewRequireSkipButton:(UIView*)view {
    return view == _joiningConversationView;
}

- (void)onFinishedFadingIn:(UIView *)view duration:(float)duration meta:(id)meta {
    [_forwardButton setHidden:!_isSkipButtonRequired && ![self doesViewRequireSkipButton:view]];
}


@end

