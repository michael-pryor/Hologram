//
//  MyClass.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionViewController.h"
#import "MediaController.h"
#import "FacebookLoginViewController.h"
#import "HologramLogin.h"
#import "AlertViewController.h"
#import "Threading.h"
#import "AccessDialog.h"
#import "ViewInteractions.h"
#import "Timer.h"
#import "Analytics.h"
#import "BannedViewController.h"
#import "UniqueId.h"
#import "ViewTransitions.h"
#import "ViewStringFormatting.h"

@implementation ConnectionViewController {
    // Connection
    id <ConnectionGovernor> _connection;
    ConnectionCommander *_connectionCommander;

    // Audio/Video
    MediaController *_mediaController;

    // GPS
    GpsState *_gpsState;

    // Social
    SocialState *_socialState;

    // DNS
    DnsResolver *_dnsResolver;
    NSString *_cachedResolvedDns;

    // UI
    volatile AlertViewController *_disconnectViewController;
    IBOutlet UIImageView *_cameraView;
    IBOutlet UIImageView *_natPunchthroughIndicator;
    IBOutlet UILabel *_ownerName;
    IBOutlet UILabel *_ownerAge;
    IBOutlet UILabel *_remoteName;
    IBOutlet UILabel *_remoteAge;
    IBOutlet UILabel *_remoteDistance;
    __weak IBOutlet UIProgressView *_ownerKarma;

    // UI - show connectivity issues.
    __weak IBOutlet UIView *_dcVideo;
    __weak IBOutlet UIView *_dcAudio;
    __weak IBOutlet UIView *_dcAudioClear;

    __weak IBOutlet UIButton *_backButton;
    __weak IBOutlet UIButton *_forwardsButton;
    UIColor *_buttonsStartingColour;

    // State
    // These three booleans are the most important.

    // Waiting for a full blown audio/video chat to start.
    volatile bool _waitingForCompleteMatch;

    // Waiting to receive a match which we can approve.
    volatile bool _waitingForProspectiveMatch;

    // We've approved and now after the conversation ends we should give a rating.
    volatile bool _shouldRateAfterSessionEnd;

    bool _isConnectionActive;
    bool _isScreenInUse;
    bool _hasHadAtLeastOneConversation;
    bool _inDifferentView;

    // Packets
    ByteBuffer *_skipPersonPacket;
    ByteBuffer *_permDisconnectPacket;

    // Special case where we want user to be able to skip, even if not currently talking
    // with somebody. Current special cases include:
    // - When user has temporarily disconnected; if user doesn't want to wait and wants to get a new match.
    volatile bool _isSkippableDespiteNoMatch;

    // Checks access to microphone, speakers and GPS.
    AccessDialog *_accessDialog;

    // Google analytics.
    NSString *_screenName;
    Timer *_connectionStateTimer;
    NatState previousState;
    Timer *_connectingNetworkTimer;     // Track how long took to connect to network.
    Timer *_connectionTemporarilyDisconnectTimer;    // Track how long we were disconnected for, before reconnecting.
    DeferredEvent *_videoDataLossAnalytics;
    DeferredEvent *_audioDataLossAnalytics;
    DeferredEvent *_audioResetAnalytics;

    // Backgrounding.
    bool _isInBackground;
    Signal *_resumeAfterBecomeActive;
    uint _backgroundCounter;

    // Karma
    uint _karmaMax;
    uint _ratingTimeoutSeconds;
    uint _matchDecisionTimeout;
    Payments *_payments;
    NSData *_karmaRegenerationReceipt;

    // How long in current conversation.
    Timer *_conversationDuration;

}

// View initially load; happens once per process.
// Essentially this is the constructor.
- (void)viewDidLoad {
    [super viewDidLoad];

    _buttonsStartingColour = [_forwardsButton titleColorForState:UIControlStateNormal];

    _hasHadAtLeastOneConversation = false;

    _socialState = nil;

    _backgroundCounter = 0;


    // Hack for arden crescent, should be nil.
    //_cachedResolvedDns = @"192.168.1.92";
    _cachedResolvedDns = nil;

    _payments = [[Payments alloc] initWithDelegate:self];

    _screenName = @"VideoChat";
    _connectionStateTimer = [[Timer alloc] init];
    _connectingNetworkTimer = [[Timer alloc] init];
    _connectionTemporarilyDisconnectTimer = [[Timer alloc] init];

    _inDifferentView = false;
    _isSkippableDespiteNoMatch = false;
    _resumeAfterBecomeActive = [[Signal alloc] initWithFlag:false];

    [self setDisconnectStateWithShortDescription:@"Initializing Core" askForConversationRating:false];

    // If failure action is triggered, application is guaranteed to be terminated by
    // _accessDialog (we may just be waiting for a user to acknowledge a dialog box).
    //
    // This is important, because we can't recover from terminateCurrentSession without
    // moving out of this view controller and back in (triggering viewDidAppear).
    //
    // But because we know the application is going to be terminated, we don't care
    // about recovering.
    _accessDialog = [[AccessDialog alloc] initWithFailureAction:^{
        [self terminateCurrentSession];
    }];

    _skipPersonPacket = [[ByteBuffer alloc] init];
    [_skipPersonPacket addUnsignedInteger8:SKIP_PERSON];

    _permDisconnectPacket = [[ByteBuffer alloc] init];
    [_permDisconnectPacket addUnsignedInteger8:DISCONNECT_PERM];

    _waitingForCompleteMatch = true;
    _waitingForProspectiveMatch = true;
    _shouldRateAfterSessionEnd = false;

    _isConnectionActive = false;

    _gpsState = [[GpsState alloc] initWithNotifier:self timeout:5];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillRetakeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];

    _isInBackground = false;
    _isScreenInUse = false;

    _dnsResolver = [[DnsResolver alloc] initWithNotifier:self dnsHost:@"app.commander.thehologram.org" timeout:5];

    const uint analyticsPublishFreqSeconds = 60;
    _videoDataLossAnalytics = [[Analytics getInstance] deferEventWithFrequencySeconds:analyticsPublishFreqSeconds category:@"network" action:@"video_loss"];
    _audioDataLossAnalytics = [[Analytics getInstance] deferEventWithFrequencySeconds:analyticsPublishFreqSeconds category:@"network" action:@"audio_loss"];
    _audioResetAnalytics = [[Analytics getInstance] deferEventWithFrequencySeconds:analyticsPublishFreqSeconds category:@"network" action:@"audio_reset"];

    _karmaMax = 0;
    _karmaRegenerationReceipt = nil;

    _conversationDuration = [[Timer alloc] init];
}

// Permanently close our session on the server, disconnect and stop media input/output.
// In order to resume, we need to reconnect to commander and get a brand new session.
- (void)terminateCurrentSession {
    // Notify server that we want to fully disconnect; server will close connection when it receives
    // notification. This prevents end point from thinking this could be a temporary disconnect.
    if (_connection != nil && _isConnectionActive) {
        [_connection disableReconnecting];
        [_connection sendTcpPacket:_permDisconnectPacket];
    }

    if (_connectionCommander != nil) {
        [_connectionCommander terminate];
    }

    // Don't push anything to the display, might get a few lingering packets received after this point.
    _isConnectionActive = false;
}

// View disappears; happens if user switches app or moves from a different view controller.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    _isScreenInUse = false;

    [self stop];
}

// Doesn't terminate the session, remains connected but pauses media input/output
// Once reconnecting, this resumes and hopefully we're still connected (if not we recover
// down the usual disconnection logic).
- (void)appWillResignActive:(NSNotification *)note {
    _isInBackground = true;
    if (!_isScreenInUse) {
        return;
    }

    // After 10 seconds, disconnect. iOS may let app run in background for a long time, don't want to
    // match with somebody if this is the case.
    __block uint backgroundCounterOriginal = _backgroundCounter;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) 10 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized (_resumeAfterBecomeActive) {
            if (_backgroundCounter != backgroundCounterOriginal) {
                NSLog(@"Not pausing operations, we have resumed since then");
                return;
            }

            NSLog(@"Pausing operation because inactive for too long");
            [_resumeAfterBecomeActive signalAll];

            [self stop];

            NSLog(@"Returned");
        }
    });
}

- (void)appWillRetakeActive:(NSNotification *)note {
    _isInBackground = false;
    if (!_isScreenInUse) {
        return;
    }

    @synchronized (_resumeAfterBecomeActive) {
        _backgroundCounter++;
        if ([_resumeAfterBecomeActive clear]) {
            NSLog(@"Resuming operation after becoming active again");
            [self start];
        }
    }
}

// View appears; happens if user switches app or moves from a different view controller.
//
// Update state; if facebook information not loaded, move to facebook view controller.
// Start by loading facebook information, then do GPS and then start connection to commander.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Reset notifications. This is in case we were waiting in the FB view contoller for the furation,
    // a badge would appear on our icon which would only go away when user goes out of app and then back in again.
    // This resets it as soon as user starts connecting again.
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    [[UIApplication sharedApplication] cancelAllLocalNotifications];

    // A sanity call, in case anything was left running while we went away.
    [self terminateCurrentSession];

    if (_disconnectViewController != nil) {
        [_disconnectViewController reset];
        [_disconnectViewController setGenericInformationText:nil skipButtonEnabled:false];
    }

    _isScreenInUse = true;
    [self start];
}

- (void)start {
    [self setDisconnectStateWithShortDescription:@"Initializing" askForConversationRating:false];

    // Start off in routed mode.
    previousState = NONE;
    [self resetFlags];
    [self onNatPunchthrough:nil stateChange:ROUTED];

    // Will probably already be there if we have already loaded previously.
    if (_disconnectViewController != nil && _inDifferentView) {
        [[Analytics getInstance] pushScreenChange:[_disconnectViewController getScreenName]];
    }

    _inDifferentView = false;
    _isSkippableDespiteNoMatch = false;

    // Important that we don't validate access to video/microphone before Facebook
    // login is complete, because its in that view controller that the dialog box about
    // how we use the video/microphone is displayed.
    SocialState *socialState = [SocialState getSocialInstance];
    //[socialState updateFromFacebookCore];
    if (![socialState isDataLoadedAndEulaAccepted] || ![[NSUserDefaults standardUserDefaults] boolForKey:@"permissionsExplanationShown"]) {
        [self switchToFacebookLogonView];
        return;
    }

    // This step can take a few seconds (particularly on older devices).
    if (_mediaController == nil) {
        _mediaController = [[MediaController alloc] initWithImageDelegate:self mediaDataLossNotifier:self];
    }

    [_videoDataLossAnalytics start];
    [_audioDataLossAnalytics start];
    [_audioResetAnalytics start];

    if (_disconnectViewController == nil) {
        [_mediaController startAudio];
    }

    if (_disconnectViewController == nil || [_disconnectViewController shouldVideoBeOn]) {
        [_mediaController startVideo];
    }

    [self onSocialDataLoaded:socialState];
}

- (void)stop {
    [self terminateCurrentSession];

    [_videoDataLossAnalytics pause];
    [_audioDataLossAnalytics pause];
    [_audioResetAnalytics pause];

    [_mediaController stopAudio];
    [_mediaController stopVideo];
}

// Callback for social data (Facebook).
// Triggers GPS loading.
- (void)onSocialDataLoaded:(SocialState *)state {
    _socialState = state;

    dispatch_sync_main(^{
        [_ownerName setText:[state humanShortName]];

        uint age = [state age];
        if (age > 0) {
            [_ownerAge setText:[ViewStringFormatting getAgeString:age]];
            [_ownerAge setHidden:false];
        } else {
            [_ownerAge setHidden:true];
        }

        [self setDisconnectStateWithShortDescription:@"Loading Apple information" askForConversationRating:false];
        [_payments queryProducts:[[UniqueId getUniqueIdInstance] getUUID]];
    });
}

// Callback for payments data loading.
// Triggers GPS loading.
- (void)onPaymentProductsLoaded {
    [self setDisconnectStateWithShortDescription:@"Loading GPS details" askForConversationRating:false];
    [_gpsState update];
}

// Callback for GPS data.
// Triggers DNS resolution.
- (void)onGpsDataLoaded:(GpsState *)state {
    if (!_isScreenInUse) {
        return;
    }

    HologramLogin *loginProvider = [[HologramLogin alloc] initWithGpsState:state regenerateKarmaReceipt:_karmaRegenerationReceipt];
    _karmaRegenerationReceipt = nil; // It's been used in this login now, regardless of whether it is successful.

    _connectionCommander = [[ConnectionCommander alloc] initWithRecvDelegate:self connectionStatusDelegate:self governorSetupDelegate:self loginProvider:loginProvider punchthroughNotifier:self];

    if (_cachedResolvedDns != nil) {
        [self connectToCommander:_cachedResolvedDns];
        return;
    }

    [self setDisconnectStateWithShortDescription:@"Resolving DNS" askForConversationRating:false];
    [_dnsResolver startResolvingDns];
}

// Callback for DNS resolution.
// Triggers connection to commander.
- (void)onDnsSuccess:(NSString *)resolvedHostName {
    if (!_isScreenInUse) {
        return;
    }
    _cachedResolvedDns = resolvedHostName;
    [self connectToCommander:resolvedHostName];
}

- (void)connectToCommander:(NSString *)hostName {
    // Put in main thread so we have guarenteed ordering when looking at _isScreenInUse.
    dispatch_sync_main(^{
        static const int CONNECT_PORT_TCP = 12241;

        if (!_isScreenInUse) {
            return;
        }
        [_connectionCommander connectToTcpHost:hostName tcpPort:CONNECT_PORT_TCP];
        _isConnectionActive = true;
    });
}

// On failure retrieving GPS failure, retry every 2 seconds.
- (void)onGpsDataLoadFailure:(GpsState *)state withDescription:(NSString *)description {
    [self setDisconnectStateWithShortDescription:@"Failed to load GPS details, retrying" askForConversationRating:false];

    // Try again in 2 seconds time.
    // Note this is just updating the UI. After failure, GPS automatically keeps retrying so needs
    // no further calls. But after two seconds we want the user to feel like we are doing something if
    // the situation hasn't improved.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![state isLoaded]) {
            [self setDisconnectStateWithShortDescription:@"Loading GPS details" askForConversationRating:false];
        }
    });
}

// Switch to the facebook logon view controller.
- (void)switchToFacebookLogonView {
    // We are the entry point, so we push to the Facebook view controller.
    if (_inDifferentView) {
        return;
    }

    dispatch_sync_main(^{
        _inDifferentView = true;

        if (_disconnectViewController != nil) {
            [_disconnectViewController signalMovingToFacebookController];
        }

        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        FacebookLoginViewController *viewController = (FacebookLoginViewController *) [storyboard instantiateViewControllerWithIdentifier:@"FacebookView"];
        [self.navigationController pushViewController:viewController animated:YES];
    });
}


// Called when we receive a change in connection state regarding NAT punchthrough.
// Important to update the display so that we know how we are connected.
//
// Note: this is called immediately after full match, right before video call starts.
- (void)onNatPunchthrough:(ConnectionGovernorNatPunchthrough *)connection stateChange:(NatState)state {
    dispatch_sync_main(^{
        if (previousState == state) {
            return;
        }

        // Conversation has started.
        [_conversationDuration reset];

        NatState previousStateLocal = previousState;
        previousState = state;
        NSTimeInterval secondsTimed = [_connectionStateTimer getSecondsSinceLastTick];
        [_connectionStateTimer reset];

        if (state == ROUTED) {
            NSLog(@"Regressed to routing mode");
            [_natPunchthroughIndicator setImage:[UIImage imageNamed:@"nat_routing_through_server"]];
        } else if (state == PUNCHED_THROUGH) {
            NSLog(@"Punched through successfully");
            [_natPunchthroughIndicator setImage:[UIImage imageNamed:@"nat_punched_through"]];
        } else if (state == ADDRESS_RECEIVED) {
            NSLog(@"**** RECEIVED NAT ADDRESS INFORMAITON FROM CLIENT *****");
            [self setDisconnectStateWithShortDescription:@"Waiting for other person to join conversation" askForConversationRating:false enableSkipButton:false];

            // At this point we are receiving connection details for a client ready to video chat with us,
            // so we're not waiting for complete or prospective match.
            _waitingForCompleteMatch = false;
            _waitingForProspectiveMatch = false;

            // We've accepted each other and video is about to start.
            _shouldRateAfterSessionEnd = true;
        } else {
            NSLog(@"Unsupported punchthrough state received");
        }

        // How long we spent routed through server vs peer to peer, across lifetime of chat.
        if (state != ADDRESS_RECEIVED) {
            if (previousStateLocal == ROUTED || previousStateLocal == ADDRESS_RECEIVED) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"conversation" name:@"via_server" label:@"routing"];
            } else if (previousStateLocal == PUNCHED_THROUGH) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"conversation" name:@"peer_to_peer" label:@"routing"];
            }

            // Time it took to punch through NAT and establish peer to peer connection.
            if (previousStateLocal == ADDRESS_RECEIVED && state == PUNCHED_THROUGH) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"setup" name:@"punch_through" label:@"routing"];
            }

            // Total time spent in conversation.
            if ((previousStateLocal == ADDRESS_RECEIVED || previousStateLocal == PUNCHED_THROUGH) && state == ROUTED) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"conversation" name:@"duration" label:@"total"];
            }
        } else {
            // Time it took to complete matching process on server side.
            // In theory, can only be ROUTED prior to this, but shouldn't matter either way.
            // If server sends us an address, then we need to interact with the client at that address.
            [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"setup" name:@"finding_match"];
        }
    });
}

/**
 * Note: during reconnects we get NAT punchthrough information only, so that is why _waitingForProspectiveMatch is set to false
 * when receiving NAT information, and why it's okay that setName doesn't get called.
 */
- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance karma:(uint)localKarmaRating maxKarma:(uint)maxKarma {
    NSLog(@"**** LOADED PROFILE DETAILS OF MATCH *****");

    // Just matched with somebody new, but they need to accept or reject us before video starts.
    _shouldRateAfterSessionEnd = false;
    _waitingForProspectiveMatch = false;

    dispatch_sync_main(^{
        NSLog(@"**** PUSHED PROFILE DETAILS OF MATCH TO DISCONNECT VIEW CONTROLLER *****");

        float localKarmaPercentage = [self getKarmaPercentage:localKarmaRating];

        NSLog(@"Received our karma of [%.3f]", localKarmaPercentage);
        [ViewStringFormatting updateKarmaUsingProgressView:_ownerKarma ratio:localKarmaPercentage];

        [_disconnectViewController setName:name profilePicture:profilePicture callingCardText:callingCardText age:age distance:distance karma:localKarmaRating maxKarma:maxKarma];

        NSLog(@"Connected with user named [%@] with age [%u]", name, age);
        [_backButton setHidden:false];
        [_forwardsButton setTitleColor:_buttonsStartingColour forState:UIControlStateNormal];

        [_remoteName setText:name];

        if (age > 0) {
            [_remoteAge setText:[ViewStringFormatting getAgeString:age]];
            [_remoteAge setHidden:false];
        } else {
            [_remoteAge setHidden:true];
        }

        NSString *distanceString = [ViewStringFormatting getStringFromDistance:distance];
        [_remoteDistance setText:distanceString];

        NSLog(@"Distance from other user: %d, producing string: %@", distance, distanceString);
        [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"distance" label:nil value:@(distance)];
    });
}

- (void)handleKarmaMaximum:(uint)karmaMaximum ratingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeout:(uint)matchDecisionTimeout {
    _karmaMax = karmaMaximum;
    _ratingTimeoutSeconds = ratingTimeoutSeconds;
    _matchDecisionTimeout = matchDecisionTimeout;

    if (_disconnectViewController != nil) {
        [_disconnectViewController setRatingTimeoutSeconds:_ratingTimeoutSeconds matchDecisionTimeoutSeconds:_matchDecisionTimeout];
    }

    NSLog(@"Karma maximum of %d loaded", karmaMaximum);
    NSLog(@"Rating timeout of %d seconds loaded", ratingTimeoutSeconds);
    NSLog(@"Match decision timeout of %d seconds loaded", matchDecisionTimeout);
}

- (float)getKarmaPercentage:(uint)karmaValue {
    return [ViewStringFormatting getKarmaRatioFromValue:karmaValue maximum:_karmaMax];
}

// Received a new image from network.
// Update the UI.
- (void)onNewImage:(UIImage *)image {
    dispatch_sync_main(^{
        if (_disconnectViewController != nil) {
            // Waiting for server to match us with somebody new.
            if (![self isReadyForChat]) {
                return;
            }

            if (![_disconnectViewController hideIfVisibleAndReady]) {
                return;
            } else {
                NSLog(@"***** CLEANING UP DISCONNECT VIEW CONTROLLER");
                _disconnectViewController = nil;
                _isSkippableDespiteNoMatch = false;
                [_mediaController clearLocalImageDelegate];
                [self prepareRuntimeView];
                [[Analytics getInstance] pushScreenChange:_screenName];

                if (!_hasHadAtLeastOneConversation) {
                    _hasHadAtLeastOneConversation = true;
                }
            }
        }
        [_cameraView setImage:image];
    });
}

// User swiped right -> skip person.
// User swiped left <- goto facebook view controller.
- (IBAction)showGestureForSwipeRecognizer:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft) {
        [self doSkipPerson];
    } else {
        [self doGotoFbLogonView];
    }
}

- (IBAction)onSkipPersonButtonPress:(id)sender {
    [self doSkipPerson];
}

- (IBAction)onGotoFbLogonViewButtonPress:(id)sender {
    [self doGotoFbLogonView];
}

- (void)doSkipPerson {
    if (_waitingForProspectiveMatch && !_isSkippableDespiteNoMatch) {
        NSLog(@"Ignoring skip request, nobody to skip");
        return;
    }

    _isSkippableDespiteNoMatch = false;

    [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"ended" label:@"skip_initiated"];

    NSLog(@"Sending skip request");
    [_connection sendTcpPacket:_skipPersonPacket];
    [self resetFlags];
    [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with\nYou skipped the other person" askForConversationRating:true];
    return;
}

- (void)doGotoFbLogonView {
    [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"ended" label:@"login_screen"];
    [self switchToFacebookLogonView];
}

// Received server details from commander and have connected.
- (void)onNewGovernor:(id <ConnectionGovernor>)governor {
    if (_connection != nil) {
        [_connection terminate];
    }
    _connection = governor;

    [_mediaController setNetworkOutputSessionUdp:[_connection getUdpOutputSession]];
}

// Handle change in connection state.
- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);

    switch (status) {
        case P_CONNECTING:
            [self setDisconnectStateWithShortDescription:@"Connecting" askForConversationRating:false];
            [_connectingNetworkTimer reset];
            break;

        case P_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with" askForConversationRating:false];
            if (_mediaController != nil) {
                [_mediaController resetSendRate];
            }
            [[Analytics getInstance] pushTimer:_connectingNetworkTimer withCategory:@"setup" name:@"network_connecting" label:@"new_session"];
            break;

        case P_CONNECTED_TO_EXISTING: {
            NSString *textToUse;
            bool inConversation = [self isReadyForChat];
            if (!inConversation) {
                textToUse = @"Matching you with somebody to talk with";
            } else {
                textToUse = @"Reconnected to existing session";
            }

            // Only enable skip button if in a conversation, not if waiting to be matched.
            [self setDisconnectStateWithShortDescription:textToUse askForConversationRating:false enableSkipButton:inConversation];
            [[Analytics getInstance] pushTimer:_connectingNetworkTimer withCategory:@"setup" name:@"network_connecting" label:@"resumed_session"];

            // How long were we disconnected for?
            [[Analytics getInstance] pushTimer:_connectionTemporarilyDisconnectTimer withCategory:@"conversation" name:@"disconnected" label:@"routing"];
        }
            break;

        case P_NOT_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected" askForConversationRating:false];
            [_connectionTemporarilyDisconnectTimer reset];
            [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"ended" label:@"network_disconnect"];
            break;

        case P_NOT_CONNECTED_HASH_REJECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected\nPrevious session timed out" askForConversationRating:false];

            // This will trigger a new commander connection, without having to wait for
            // another DNS resolution; we'll just use the last one we did.
            if (_cachedResolvedDns != nil) {
                [self onDnsSuccess:_cachedResolvedDns];
            } else {
                // Try to look from storage in case something went wrong, but really _cachedResolvedDns should always be populated.
                [_dnsResolver lookupWithoutNetwork];
            }
            break;

        default:
            NSLog(@"Bad connection state");
            [_connectionCommander shutdown];
            break;
    }
}

- (void)onBannedWithMagnitude:(uint8_t)magnitude expiryTimeSeconds:(uint)numSeconds {
    dispatch_sync_main(^{
        _inDifferentView = true;

        if (_disconnectViewController != nil) {
            [_disconnectViewController signalMovingToFacebookController];
        }

        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        BannedViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"BannedViewController"];

        SKProduct *product = [_payments getKarmaProductWithMagnitude:magnitude];

        [viewController setWaitTime:numSeconds paymentProduct:product payments:_payments transactionCompletedNotifier:self];
        [self.navigationController pushViewController:viewController animated:YES];
    });
}

- (bool)isReadyForChat {
    return _shouldRateAfterSessionEnd && !_waitingForCompleteMatch && !_waitingForProspectiveMatch;
}

- (void)setDisconnectStateWithShortDescription:(NSString *)shortDescription askForConversationRating:(bool)askForConversationRating {
    [self setDisconnectStateWithShortDescription:shortDescription askForConversationRating:askForConversationRating enableSkipButton:false];
}

// Display view overlay showing how connection is being recovered.
- (void)setDisconnectStateWithShortDescription:(NSString *)shortDescription askForConversationRating:(bool)askForConversationRating enableSkipButton:(bool)enableSkipButton {
    // If we haven't accepted or rejected the client yet, then don't ask to rate the conversation,
    // since we can't have had one.
    if (!_shouldRateAfterSessionEnd) {
        askForConversationRating = false;
    }

    void (^block)() = ^{
        dispatch_sync_main(^{
            if (_inDifferentView) {
                NSLog(@"***** IN DIFFERENT VIEW, NOT INITIALIZING DISCONNECT VIEW CONTROLLER");
                return;
            }

            // Show the disconnect storyboard.
            bool alreadyPresented = _disconnectViewController != nil;
            if (!alreadyPresented) {
                [self preprepareRuntimeView];

                NSLog(@"***** INSTANTIATED DISCONNECT VIEW CONTROLLER *****");
                _disconnectViewController = (AlertViewController *) [ViewTransitions initializeViewControllerFromParent:self name:@"DisconnectAlertView"];

                if (_hasHadAtLeastOneConversation) {
                    [_disconnectViewController enableAdverts];
                }

                if (_mediaController != nil) {
                    [_mediaController setLocalImageDelegate:_disconnectViewController];
                }

                [ViewTransitions loadViewControllerIntoParent:self child:_disconnectViewController];
            } else {
                NSLog(@"***** REUSING EXISTING DISCONNECT VIEW CONTROLLER *****");
                if (_mediaController != nil) {
                    [_mediaController setLocalImageDelegate:_disconnectViewController];
                }
            }
            // Set its content
            [_disconnectViewController setConversationRatingConsumer:self matchingAnswerDelegate:self mediaOperator:_mediaController];
            [_disconnectViewController setRatingTimeoutSeconds:_ratingTimeoutSeconds matchDecisionTimeoutSeconds:_matchDecisionTimeout];
            [_disconnectViewController setGenericInformationText:shortDescription skipButtonEnabled:enableSkipButton];
            [_disconnectViewController setConversationEndedViewVisible:askForConversationRating showQuickly:false];

            if (!alreadyPresented) {
                NSLog(@"***** PRESENTING DISCONNECT VIEW CONTROLLER *****");
                [ViewTransitions presentViewController:self child:_disconnectViewController];

                // Important so that we don't notify google analytics of screen change, whilst inside FB view.
                if (!_inDifferentView) {
                    [[Analytics getInstance] pushScreenChange:[_disconnectViewController getScreenName]];
                }
            }
        });
    };

    if (_accessDialog != nil) {
        [_accessDialog validateAuthorization:^{
            block();
        }];
    } else {
        block();
    }
}

- (void)resetFlags {
    _waitingForProspectiveMatch = true;
    _waitingForCompleteMatch = true;

    // Note: I have deliberately not included _shouldRateAfterSessionEnd!
}

// Handle data and pass to relevant parts of application.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (!_isConnectionActive) {
        return;
    }

    if (protocol == TCP) {
        uint operation = [packet getUnsignedIntegerAtPosition8:0];
        if (operation == DISCONNECT_TEMP) {
            // Allow user to skip if doesn't want to wait for previous user to reconnect.
            _isSkippableDespiteNoMatch = true;

            NSLog(@"End point temporarily disconnected");
            [self setDisconnectStateWithShortDescription:@"Reconnecting to existing session\nThe other person disconnected temporarily" askForConversationRating:false enableSkipButton:true];
        } else if (operation == DISCONNECT_PERM) {
            NSLog(@"End point permanently disconnected");

            [self resetFlags];
            [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with\nThe other person left" askForConversationRating:true];
        } else if (operation == DISCONNECT_SKIPPED) {
            NSLog(@"End point skipped us");

            _waitingForCompleteMatch = true;
            // Excluded prospective match, because we still want user to feel like they can reject too.

            [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with\nThe other person skipped you" askForConversationRating:true];
        } else {
            if (_mediaController != nil) {
                [_mediaController onNewPacket:packet fromProtocol:protocol];
            }
        }
    } else {
        // Waiting for server to match us with somebody new.
        if (_waitingForCompleteMatch) {
            return;
        }

        // Don't show audio until user is visible.
        if ([_mediaController isAudioPacket:packet] && _disconnectViewController != nil) {
            return;
        }

        // Do not update screen in background, because its expensive and we get warnings about GPU in the logs.
        if (_mediaController != nil && !_isInBackground) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    }
}

- (void)onMediaDataLossFromSender:(MediaType)mediaType {
    // Must be async to avoid deadlock.
    //
    // Specifically, we may send a data loss notification from within an audio priority queue serving the speaker.
    // At the same time, we may attempt to shut down the audio I/O (including this speaker) from the main thread.
    // The main thread would wait for the speaker to finish, which needs the audio priority queue to release, so
    // both are waiting for each other forever!
    dispatch_async_main(^{
        // Between conversations we always get some data loss, so don't tell user about it.
        if (_waitingForCompleteMatch || [_conversationDuration getSecondsSinceLastTick] < 2) {
            return;
        }

        if (mediaType == VIDEO) {
            NSLog(@"Data loss for video!");
            [ViewInteractions fadeInOut:_dcVideo completion:nil options:UIViewAnimationOptionBeginFromCurrentState];
            [_videoDataLossAnalytics increment];
        } else if (mediaType == AUDIO) {
            NSLog(@"Data loss for audio!");
            [ViewInteractions fadeInOut:_dcAudio completion:nil options:UIViewAnimationOptionBeginFromCurrentState];
            [_audioDataLossAnalytics increment];
        } else if (mediaType == AUDIO_QUEUE_RESET) {
            NSLog(@"Extreme audio data loss (audio queue reset)!");
            [ViewInteractions fadeInOut:_dcAudioClear completion:nil options:UIViewAnimationOptionBeginFromCurrentState];
            [_audioResetAnalytics increment];
        } else {
            NSLog(@"Unknown data loss type");
        }
    }, 0);
}

- (void)preprepareRuntimeView {
    dispatch_sync_main(^{
        [_cameraView.layer removeAllAnimations];
        [_ownerAge setAlpha:0.0f];
        [_ownerName setAlpha:0.0f];
        [_remoteAge setAlpha:0.0f];
        [_remoteName setAlpha:0.0f];
        [_cameraView setAlpha:0.0f];
        [_remoteDistance setAlpha:0.0f];
        [_ownerKarma setAlpha:0.0f];
    });
}

- (void)prepareRuntimeView {
    [ViewInteractions fadeIn:_cameraView completion:nil duration:1.0f];

    [ViewInteractions fadeIn:_remoteName completion:^(BOOL completedNext) {
        if (!completedNext || _disconnectViewController != nil) {
            return;
        }
        [ViewInteractions fadeIn:_remoteAge completion:^(BOOL completedNextB) {
            if (!completedNextB || _disconnectViewController != nil) {
                return;
            }
            [ViewInteractions fadeIn:_remoteDistance completion:nil duration:2.0f];
        }               duration:2.0f];
    }               duration:2.0f];

    [ViewInteractions fadeIn:_ownerKarma completion:^(BOOL completed) {
        if (!completed || _disconnectViewController != nil) {
            return;
        }
        [ViewInteractions fadeIn:_ownerName completion:^(BOOL completedNext) {
            if (!completedNext || _disconnectViewController != nil) {
                return;
            }
            [ViewInteractions fadeIn:_ownerAge completion:nil duration:2.0f];
        }               duration:2.0f];
    }               duration:2.0f];
}

- (void)onConversationRating:(ConversationRating)conversationRating {
    ByteBuffer *buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger8:PREVIOUS_CONVERSATION_RATING];
    [buffer addUnsignedInteger8:conversationRating];
    [_connection sendTcpPacket:buffer];
}

- (void)onTransactionCompleted:(NSData *)data {
    _karmaRegenerationReceipt = data;
}

- (void)onMatchAcceptAnswer {
    NSLog(@"Accepted conversation, sending accept packet");
    ByteBuffer *buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger8:ACCEPTED_CONVERSATION];
    [_connection sendTcpPacket:buffer];
}

- (bool)onMatchRejectAnswer {
    NSLog(@"Rejected conversation, skipping and rating");
    [self doSkipPerson];
    return true;
}

- (void)onMatchBlocked {
    NSLog(@"Blocked and reported match");
    [self onConversationRating:S_BLOCK];
    [self resetFlags];
}

- (void)onBackToSocialRequest {
    [self onGotoFbLogonViewButtonPress:self];
}

- (void)onInactivityRejection {
    NSLog(@"Server kicked us off due to inactivity, moving back to social view controller");
    [self onBackToSocialRequest];
}

@end
