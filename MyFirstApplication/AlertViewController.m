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

#define MINIMUM_WAIT_TIME 3.0

@implementation AlertViewController {
    // Base view, describing state of app and connection.
    __weak IBOutlet UIImageView *_localImageView;
    __weak IBOutlet UIView *_localImageViewParent;
    IBOutlet UILabel *_alertShortText;
    __weak IBOutlet UILabel *_alertShortTextHigher;
    __weak IBOutlet UIButton *_backButton;
    id <MediaOperator> _mediaOperator;
    bool _movingToFacebook;
    bool _viewVisible;

    // Advert.
    Timer *_timerSinceAdvertCreated;
    __weak IBOutlet UIView *_advertBannerView; // The container which sizes it.
    FBAdView *_advertView; // The actual advert.
    bool _shouldShowAdverts;

    // Rating previous conversation..
    __weak IBOutlet UIView *_conversationEndView;
    ConversationEndedViewController *_conversationEndViewController;
    id <ConversationRatingConsumer> _conversationRatingConsumer;
    uint _ratingTimeoutSeconds;
    Signal *_waitingForRating;


    // Matching i.e. viewing cards.
    __weak IBOutlet UIView *_matchingView;
    MatchingViewController *_matchingViewController;
    id <MatchingAnswerDelegate> _matchingAnswerDelegate;

    // Accepted a match, waiting for other side to accept too.
    __weak IBOutlet UIView *_joiningConversationView;
    JoiningViewController *_joiningConversationViewController;

    // All views, we only have one visible at a time.
    SingleViewCollection *_viewCollection;
}

- (bool)isViewCurrent:(UIView *)view {
    return [_viewCollection isViewDisplayedWideSearch:view];
}

- (bool)isInConversationEndedView {
    return [self isViewCurrent:_conversationEndView];
}

- (bool)isInMatchApprovalView {
    return [self isViewCurrent:_matchingView];
}
- (bool)shouldVideoBeOnView:(UIView*)view {
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
}

- (void)setGenericInformationText:(NSString *)shortText {
    dispatch_sync_main(^{
        // Alert text has changed, wait at least two seconds more before clearing display.
        [_timerSinceAdvertCreated reset];

        _alertShortText.text = shortText;
        [_alertShortText setNeedsDisplay];
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

    _viewVisible = false;
    _waitingForRating = [[Signal alloc] initWithFlag:false];

    for (UIView *view in @[_conversationEndView, _matchingView, _joiningConversationView, _localImageViewParent, _alertShortTextHigher]) {
        [view setAlpha:0];
    }

    _viewCollection = [[SingleViewCollection alloc] initWithDuration:0.5f viewChangeNotifier:self];
    _conversationRatingConsumer = nil;
    _ratingTimeoutSeconds = 0;
    _movingToFacebook = false;
    _shouldShowAdverts = false;

    // This is always the first view to be shown!
    // And we need the video to be running so that messages can be sent across,
    // client only removes view controller when image is received.
    //[self showView:_localImageViewParent instant:true];

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
    _viewVisible = true;

    NSLog(@"!!!!!!APPEAR!!!!!!");

    _movingToFacebook = false;
    [_mediaOperator stopAudio];

    [_timerSinceAdvertCreated setSecondsFrequency:MINIMUM_WAIT_TIME];
    [_timerSinceAdvertCreated reset];

    NSLog(@"Disconnect view controller loaded, unhiding banner advert and setting delegate");

    // Use hidden flag on appear/disappear, in case it impacts decision to display adds.
    if (_shouldShowAdverts) {
        [_advertBannerView setHidden:false];
        [_advertView loadAd];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _viewVisible = false;

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
}

- (IBAction)onForwardButtonPress:(id)sender {
    [self onMatchRejectAnswer];
}

- (void)hideViewsInstant:(bool)instant {
    [self showView:_localImageViewParent instant:instant];
}

- (void)showView:(UIView *)viewToShow instant:(bool)instant {
    if (viewToShow == _localImageViewParent) {
        [_viewCollection displayView:viewToShow ifNoChangeForMilliseconds:1000];
        return;
    }

    [_viewCollection displayView:viewToShow];
}

- (void)setConversationEndedViewVisible:(bool)visible instantly:(bool)instant {
    if ([self isInMatchApprovalView] || ([self isInConversationEndedView] && visible)) {
        return;
    }

    if (visible && [_waitingForRating signalAll]) {
        [_conversationEndViewController reset];
        [self showView:_conversationEndView instant:instant];
        [self setViewRelevantInformationText:@"Please rate your previous conversation\nThis will influence their karma"];
        dispatch_async_main(^{
            [_conversationEndViewController onRatingsCompleted];
            [_waitingForRating clear];
        }, _ratingTimeoutSeconds * 1000);
    } else if (![_waitingForRating isSignaled]){
        [self hideViewsInstant:instant];
    }

}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate mediaOperator:(id <MediaOperator>)videoOperator ratingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeoutSeconds:(uint)matchDecisionTimeoutSeconds {
    _conversationRatingConsumer = consumer;
    _ratingTimeoutSeconds = ratingTimeoutSeconds;
    [_conversationEndViewController setConversationRatingConsumer:self];
    [_matchingViewController setMatchingDecisionTimeoutSeconds:matchDecisionTimeoutSeconds];
    _matchingAnswerDelegate = matchingAnswerDelegate;
    _mediaOperator = videoOperator;
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    [_conversationRatingConsumer onConversationRating:conversationRating];
    [_waitingForRating clear];
    [self setConversationEndedViewVisible:false instantly:false];
}

- (void)onMatchAcceptAnswer {
    [_matchingAnswerDelegate onMatchAcceptAnswer];
    [self setViewRelevantInformationText:@"Waiting for your match to accept too"];
    [_joiningConversationViewController consumeRemainingTimer:[_matchingViewController cloneTimer]];
    [self showView:_joiningConversationView instant:false];
}

- (void)onMatchingFinished {
    [self hideViewsInstant:false];
}

- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance {
    [_matchingViewController setName:name profilePicture:profilePicture callingCardText:callingCardText age:age distance:distance];
    [self onMatchingStarted];
}

- (void)onMatchingStarted {
    [self showView:_matchingView instant:false];
}

- (bool)onMatchRejectAnswer {
    if ([_matchingAnswerDelegate onMatchRejectAnswer]) {
        [self onMatchingFinished];
        return true;
    }

    return false;
}

- (void)onMatchBlocked {
    [_matchingAnswerDelegate onMatchBlocked];
    [self onMatchingFinished];
}

- (void)onTimedOut {
    [self onMatchingFinished];
}

- (void)onBackToSocialRequest {
    [_matchingAnswerDelegate onBackToSocialRequest];
}

- (IBAction)onGotoFbLogonViewButtonPress:(id)sender {
    [self onBackToSocialRequest];
}

- (void)onStartedFadingOut:(UIView*)view duration:(float)duration{
    if ([self isAssociatedWithAlertShortTextHigher:view]) {
        [ViewInteractions fadeOut:_alertShortTextHigher completion:^(BOOL completion) {
            if (!completion) {
                [_alertShortTextHigher setAlpha:0];
            }
        } duration:duration];
    }
}
- (void)onFinishedFadingOut:(UIView*)view duration:(float)duration{
    if ([self shouldVideoBeOnView:view]) {
        [_mediaOperator stopVideo];
    }
}

- (void)onStartedFadingIn:(UIView*)view duration:(float)duration{
    if ([self shouldVideoBeOnView:view]) {
        [_mediaOperator startVideo];
    }

    if ([self isAssociatedWithAlertShortTextHigher:view]) {
        [ViewInteractions fadeIn:_alertShortTextHigher completion:^(BOOL completion) {
            if (!completion) {
                [_alertShortTextHigher setAlpha:1];
            }
        } duration:duration];
    }
}


- (bool)isAssociatedWithAlertShortTextHigher:(UIView*)view {
    return view == _conversationEndView || view == _joiningConversationView;
}

- (void)onFinishedFadingIn:(UIView*)view duration:(float)duration{
}


@end

