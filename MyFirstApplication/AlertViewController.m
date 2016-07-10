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
    void(^_moveToFacebookViewControllerFunc)();
    NSString *_cachedAlertShortText;
    id<MediaOperator> _videoOperator;
    bool _movingToFacebook;

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


    // Matching i.e. viewing cards.
    __weak IBOutlet UIView *_matchingView;
    MatchingViewController *_matchingViewController;
    id <MatchingAnswerDelegate> _matchingAnswerDelegate;
    uint _matchDecisionTimeoutSeconds;
    bool _matchDecisionMade;

    // Accepted a match, waiting for other side to accept too.
    __weak IBOutlet UIView *_joiningConversationView;
    JoiningViewController *_joiningConversationViewController;

    // All views, we only have one visible at a time.
    NSArray *_views;
    UIView *_currentView;
}

- (bool)isViewCurrent:(UIView*)view {
    return _currentView == view;
}

- (bool)isInConversationEndedView {
    return [self isViewCurrent:_conversationEndView];
}

- (bool)isInMatchApprovalView {
    return [self isViewCurrent:_matchingView];
}

- (bool)shouldVideoBeOn {
    return _currentView == _localImageViewParent && !_movingToFacebook;
}

- (void)signalMovingToFacebookController {
    _movingToFacebook = true;
}

- (void)setAlertShortText:(NSString *)shortText {
    _cachedAlertShortText = shortText;
    if ([self isInConversationEndedView]) {
        return;
    }

    [self doSetAlertShortText:shortText];
}

- (void)doSetAlertShortText:(NSString *)shortText {
    dispatch_sync_main(^{
        // Alert text has changed, wait at least two seconds more before clearing display.
        [_timerSinceAdvertCreated reset];

        _alertShortText.text = shortText;
        _alertShortTextHigher.text = shortText;
        [_alertShortText setNeedsDisplay];
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

    _views = @[_conversationEndView, _matchingView, _joiningConversationView, _localImageViewParent];

    _currentView = nil;
    _conversationRatingConsumer = nil;
    _ratingTimeoutSeconds = 0;

    _movingToFacebook = false;

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
    
    _movingToFacebook = false;
    
    [_videoOperator stopAudio];
    [_videoOperator stopVideo];

    [_timerSinceAdvertCreated setSecondsFrequency:MINIMUM_WAIT_TIME];
    [_timerSinceAdvertCreated reset];

    NSLog(@"Disconnect view controller loaded, unhiding banner advert and setting delegate");
    [_backButton setHidden:false];

    // Use hidden flag on appear/disappear, in case it impacts decision to display adds.
    if (_shouldShowAdverts) {
        [_advertBannerView setHidden:false];
        [_advertView loadAd];
    }

    _matchDecisionMade = false;
}

- (void)viewDidDisappear:(BOOL)animated {
    // Pause the banner view, stop it loading new adverts.
    NSLog(@"Disconnect view controller hidden, hiding banner advert and removing delegate");
    [_backButton setHidden:true];
    [_advertBannerView setHidden:true];

    // Ensures state is reset, and starts the video.
    [self hideViewsInstant:true];
    if (!_movingToFacebook) {
        [_videoOperator startAudio];
    }

    [_joiningConversationViewController stop];
}

- (void)enableAdverts {
    _shouldShowAdverts = true;
}

- (void)hideNow {
    dispatch_sync_main(^{
        NSLog(@"Removing disconnect screen from parent");
        [ViewTransitions hideChildViewController:self];
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
        _movingToFacebook = true;
        _moveToFacebookViewControllerFunc();
    }
}

- (IBAction)onForwardButtonPress:(id)sender {
    [self onMatchRejectAnswer];
}


- (void)hideViewsInstant:(bool)instant {
    [self showView:nil instant:instant];
}

- (void)showView:(UIView *)viewToShow instant:(bool)instant {
    const float duration = instant ? 0 : 0.25f;

    if (viewToShow == nil ) {
        viewToShow = _localImageViewParent;
    }

    dispatch_sync_main(^{
        bool shown = false;
        
        if (viewToShow == _matchingView) {
            [ViewInteractions fadeOut:_currentView completion: ^(BOOL completed) {
                [viewToShow setAlpha:0.8f];
                [ViewInteractions fadeIn:viewToShow completion:nil duration:duration];
            } duration:duration];
            shown = true;
        } else if (viewToShow == _currentView) {
            // Nothing to do.
            shown = true;
        } else {
            for (UIView *view in _views) {
                if (view == viewToShow) {
                    continue;
                }

                if ([view alpha] > 0) {
                    if (!shown && [view alpha] == 1) {
                        if (viewToShow != nil) {
                            [ViewInteractions fadeOut:view thenIn:viewToShow duration:duration];
                        } else {
                            [ViewInteractions fadeOut:view completion:nil duration:duration];
                        }
                        shown = true;
                    } else {
                        [view setAlpha:0];
                    }
                }
            }
        }

        if (!shown && viewToShow != nil) {
            [ViewInteractions fadeIn:viewToShow completion:nil duration:duration];
            shown = true;
        }
        
        if (shown) {
            _currentView = viewToShow;
        } else {
            _currentView = nil;
        }
        
        [self onViewShown:_currentView duration:duration*3];
    });
}

- (void)onViewShown:(UIView*)view duration:(float)duration {
    if ([self shouldVideoBeOn]) {
        [_videoOperator startVideo];
        [ViewInteractions fadeIn:_alertShortText completion:nil duration:duration];

    } else {
        [_alertShortText setAlpha:0];
        [_videoOperator stopVideo];
    }

    if (view == _conversationEndView || view == _joiningConversationView) {
        [ViewInteractions fadeIn:_alertShortTextHigher completion:nil duration:duration];
    } else {
        [_alertShortTextHigher setAlpha:0];
    }
}

- (void)setConversationEndedViewVisible:(bool)visible instantly:(bool)instant {
    if ([self isInMatchApprovalView] || ([self isInConversationEndedView] && visible)) {
        return;
    }

    if (visible) {
        [_conversationEndViewController reset];
        [self showView:_conversationEndView instant:instant];
        [self doSetAlertShortText:@"Please rate your previous conversation\nThis will influence their karma"];
        dispatch_async_main(^{
            [_conversationEndViewController onRatingsCompleted];
        }, _ratingTimeoutSeconds * 1000);

    } else {
        [self hideViewsInstant:instant];
        [self doSetAlertShortText:_cachedAlertShortText];
    }

}

- (void)setConversationRatingConsumer:(id <ConversationRatingConsumer>)consumer matchingAnswerDelegate:(id <MatchingAnswerDelegate>)matchingAnswerDelegate mediaOperator:(id <MediaOperator>)videoOperator ratingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeoutSeconds:(uint)matchDecisionTimeoutSeconds {
    _conversationRatingConsumer = consumer;
    _matchDecisionTimeoutSeconds = matchDecisionTimeoutSeconds;
    _ratingTimeoutSeconds = ratingTimeoutSeconds;
    [_conversationEndViewController setConversationRatingConsumer:self];
    [_matchingViewController setMatchingDecisionTimeoutSeconds:matchDecisionTimeoutSeconds];
    _matchingAnswerDelegate = matchingAnswerDelegate;
    _videoOperator = videoOperator;
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    [self setConversationEndedViewVisible:false instantly:false];
    [_conversationRatingConsumer onConversationRating:conversationRating];
}

- (void)onMatchAcceptAnswer {
    _matchDecisionMade = true;
    [_matchingAnswerDelegate onMatchAcceptAnswer];
    [self showView:_joiningConversationView instant:false];
    [_joiningConversationViewController consumeRemainingTimer:[_matchingViewController cloneTimer]];
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

