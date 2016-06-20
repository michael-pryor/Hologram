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

@implementation ConnectionViewController {
    // Connection
    id <ConnectionGovernor> _connection;
    ConnectionCommander *_connectionCommander;

    // Audio/Video
    MediaController *_mediaController;

    // GPS
    GpsState *_gpsState;

    // UI
    volatile AlertViewController *_disconnectViewController;
    IBOutlet UIImageView *_cameraView;
    IBOutlet UIImageView *_natPunchthroughIndicator;
    IBOutlet UILabel *_ownerName;
    IBOutlet UILabel *_ownerAge;
    IBOutlet UILabel *_remoteName;
    IBOutlet UILabel *_remoteAge;
    IBOutlet UILabel *_remoteDistance;

    // UI - show connectivity issues.
    __weak IBOutlet UIView *_dcVideo;
    __weak IBOutlet UIView *_dcAudio;
    __weak IBOutlet UIView *_dcAudioClear;


    // State
    volatile bool _waitingForNewEndPoint;
    bool _isConnectionActive;

    // Packets
    ByteBuffer *_skipPersonPacket;
    ByteBuffer *_permDisconnectPacket;

    bool _inFacebookLoginView;

    // Special case where we want user to be able to skip, even if not currently talking
    // with somebody. Current special cases include:
    // - When user has temporarily disconnected; if user doesn't want to wait and wants to get a new match.
    volatile bool _isSkippableDespiteNoMatch;

    // Checks access to microphone, speakers and GPS.
    AccessDialog *_accessDialog;

    // Temporary tutorial labels.
    __weak IBOutlet UILabel *_swipeTutorialChangeSettings;
    __weak IBOutlet UILabel *_swipeTutorialSkip;

    // For Google analytics.
    NSString *_screenName;
    Timer *_connectionStateTimer;
    NatState previousState;

    // Track how long took to connect to network.
    Timer *_connectingNetworkTimer;

    // Track how long we were disconnected for, before reconnecting.
    Timer *_connectionTemporarilyDisconnectTimer;

    bool _isInBackground;
    Signal *_resumeAfterBecomeActive;
    uint _backgroundCounter;
    bool _isScreenInUse;

    bool _hasHadAtLeastOneConversation;

    DnsResolver *_dnsResolver;
    NSString *_cachedResolvedDns;

    DeferredEvent *_videoDataLossAnalytics;
    DeferredEvent *_audioDataLossAnalytics;
    DeferredEvent *_audioResetAnalytics;
}

// View initially load; happens once per process.
// Essentially this is the constructor.
- (void)viewDidLoad {
    [super viewDidLoad];

    _hasHadAtLeastOneConversation = false;

    _backgroundCounter = 0;

    // Hack for arden crescent, should be nil.
    _cachedResolvedDns = @"192.168.1.92";

    _screenName = @"VideoChat";
    _connectionStateTimer = [[Timer alloc] init];
    _connectingNetworkTimer = [[Timer alloc] init];
    _connectionTemporarilyDisconnectTimer = [[Timer alloc] init];

    _inFacebookLoginView = false;
    _isSkippableDespiteNoMatch = false;
    _resumeAfterBecomeActive = [[Signal alloc] initWithFlag:false];

    [self setDisconnectStateWithShortDescription:@"Initializing" showConversationEndView:false];

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

    _waitingForNewEndPoint = true;
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

    // Terminate microphone and video.
    [_mediaController stop];
    [_mediaController stopVideo];
}

// View disappears; happens if user switches app or moves from a different view controller.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Put in main thread so we have guarenteed ordering with isScreenInUse.
    // I don't want to start the commander when not in this view; this
    // prevents a race conditon.
    dispatch_sync_main(^{
        _isScreenInUse = false;
    });

    [self stop];
}

// Doesn't terminate the session, remains connected but pauses media input/output
// Once reconnecting, this resumes and hopefully we're still connected (if not we recover
// down the usual disconnection logic).
- (void)appWillResignActive:(NSNotification *)note {
    _isInBackground = true;

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

    // A sanity call, in case anything was left running while we went away.
    [self terminateCurrentSession];

    _isScreenInUse = true;
    [self start];
}

- (void)start {
    // Start off in routed mode.
    previousState = NONE;
    [self onNatPunchthrough:nil stateChange:ROUTED];

    // Will probably already be there if we have already loaded previously.
    if (_disconnectViewController != nil && _inFacebookLoginView) {
        [[Analytics getInstance] pushScreenChange:[_disconnectViewController getScreenName]];
    }

    _inFacebookLoginView = false;
    _isSkippableDespiteNoMatch = false;

    // Important that we don't validate access to video/microphone before Facebook
    // login is complete, because its in that view controller that the dialog box about
    // how we use the video/microphone is displayed.
    SocialState *socialState = [SocialState getFacebookInstance];
    [socialState updateCoreFacebookInformation];
    if (![socialState isBasicDataLoaded] || ![[NSUserDefaults standardUserDefaults] boolForKey:@"permissionsExplanationShown"]) {
        [self switchToFacebookLogonView];
        return;
    }

    // This step can take a few seconds (particularly on older devices).
    [self setDisconnectStateWithShortDescription:@"Initializing" showConversationEndView:false];
    if (_mediaController == nil) {
        _mediaController = [[MediaController alloc] initWithImageDelegate:self mediaDataLossNotifier:self];
    }
    [_mediaController startVideo];

    [_videoDataLossAnalytics start];
    [_audioDataLossAnalytics start];
    [_audioResetAnalytics start];

    if (![socialState isDataLoaded]) {
        [socialState registerNotifier:self];
        [self setDisconnectStateWithShortDescription:@"Loading Facebook details" showConversationEndView:false];
        if (![socialState updateGraphFacebookInformation]) {
            [self switchToFacebookLogonView];
        }
    } else {
        [self onSocialDataLoaded:socialState];
    }
}

- (void)stop {
    [self terminateCurrentSession];

    [_videoDataLossAnalytics pause];
    [_audioDataLossAnalytics pause];
    [_audioResetAnalytics pause];
}

// Callback for social data (Facebook).
// Triggers GPS loading.
- (void)onSocialDataLoaded:(SocialState *)state {
    [state unregisterNotifier];
    dispatch_sync_main(^{
        [_ownerName setText:[state humanShortName]];

        uint age = [state age];
        if (age > 0) {
            [_ownerAge setText:[NSString stringWithFormat:@"%d", age]];
            [_ownerAge setHidden:false];
        } else {
            [_ownerAge setHidden:true];
        }

        [self setDisconnectStateWithShortDescription:@"Loading GPS details" showConversationEndView:false];
        [_gpsState update];
    });
}

// Callback for GPS data.
// Starts connection.
- (void)onGpsDataLoaded:(GpsState *)state {
    if (!_isScreenInUse) {
        return;
    }

    HologramLogin *loginProvider = [[HologramLogin alloc] initWithGpsState:state];
    _connectionCommander = [[ConnectionCommander alloc] initWithRecvDelegate:self connectionStatusDelegate:self governorSetupDelegate:self loginProvider:loginProvider punchthroughNotifier:self];

    if (_cachedResolvedDns != nil) {
        [self connectToCommander:_cachedResolvedDns];
        return;
    }

    [self setDisconnectStateWithShortDescription:@"Resolving DNS" showConversationEndView:false];
    [_dnsResolver startResolvingDns];
}

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
    [self setDisconnectStateWithShortDescription:@"Failed to load GPS details, retrying" showConversationEndView:false];

    // Try again in 2 seconds time.
    // Note this is just updating the UI. After failure, GPS automatically keeps retrying so needs
    // no further calls. But after two seconds we want the user to feel like we are doing something if
    // the situation hasn't improved.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![state isLoaded]) {
            [self setDisconnectStateWithShortDescription:@"Loading GPS details" showConversationEndView:false];
        }
    });
}


// Switch to the facebook logon view controller.
- (void)switchToFacebookLogonView {
    // We are the entry point, so we push to the Facebook view controller.
    if (_inFacebookLoginView) {
        return;
    }

    dispatch_sync_main(^{
        _inFacebookLoginView = true;

        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        FacebookLoginViewController *viewController = (FacebookLoginViewController *) [storyboard instantiateViewControllerWithIdentifier:@"FacebookView"];
        [self.navigationController pushViewController:viewController animated:YES];
    });
}


// Called when we receive a change in connection state regarding NAT punchthrough.
// Important to update the display so that we know how we are connected.
- (void)onNatPunchthrough:(ConnectionGovernorNatPunchthrough *)connection stateChange:(NatState)state {
    dispatch_sync_main(^{
        if (previousState == state) {
            return;
        }
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
            NSLog(@"New end point received");
            _waitingForNewEndPoint = false;
            [_mediaController start];
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

- (void)handleUserName:(NSString *)name age:(uint)age distance:(uint)distance {
    dispatch_sync_main(^{
        NSLog(@"Connected with user named [%@] with age [%u]", name, age);
        [_remoteName setText:name];

        if (age > 0) {
            [_remoteAge setText:[NSString stringWithFormat:@"%d", age]];
            [_remoteAge setHidden:false];
        } else {
            [_remoteAge setHidden:true];
        }

        NSString *distanceString;
        if (distance <= 1) {
            distanceString = @"< 1 km away";
        } else if (distance > 15000) {
            distanceString = @"> 15000 km away";
        } else {
            distanceString = [NSString stringWithFormat:@"%d km away", distance];
        }
        [_remoteDistance setText:distanceString];

        NSLog(@"Distance from other user: %d, producing string: %@", distance, distanceString);
        [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"distance" label:nil value:@(distance)];
    });
}

// Received a new image from network.
// Update the UI.
- (void)onNewImage:(UIImage *)image {
    dispatch_sync_main(^{
        if (_disconnectViewController != nil) {
            // Waiting for server to match us with somebody new.
            if (_waitingForNewEndPoint) {
                return;
            }

            if (![_disconnectViewController hideIfVisibleAndReady]) {
                return;
            } else {
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
    if (_waitingForNewEndPoint && !_isSkippableDespiteNoMatch) {
        NSLog(@"Ignoring skip request, nobody to skip");
        return;
    }

    _isSkippableDespiteNoMatch = false;

    [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"ended" label:@"skip_initiated"];

    NSLog(@"Sending skip request");
    [_connection sendTcpPacket:_skipPersonPacket];
    [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with\nYou skipped the other person" showConversationEndView:true];
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
    [_mediaController start];
}

// Handle change in connection state.
- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);

    switch (status) {
        case P_CONNECTING:
            [self setDisconnectStateWithShortDescription:@"Connecting" showConversationEndView:false];
            [_connectingNetworkTimer reset];
            break;

        case P_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with" showConversationEndView:false];
            if (_mediaController != nil) {
                [_mediaController resetSendRate];
            }
            [[Analytics getInstance] pushTimer:_connectingNetworkTimer withCategory:@"setup" name:@"network_connecting" label:@"new_session"];
            break;

        case P_CONNECTED_TO_EXISTING:
            [self setDisconnectStateWithShortDescription:@"Reconnected to existing session" showConversationEndView:false];
            [[Analytics getInstance] pushTimer:_connectingNetworkTimer withCategory:@"setup" name:@"network_connecting" label:@"resumed_session"];

            // How long were we disconnected for?
            [[Analytics getInstance] pushTimer:_connectionTemporarilyDisconnectTimer withCategory:@"conversation" name:@"disconnected" label:@"routing"];
            break;

        case P_NOT_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected" showConversationEndView:false];
            [_connectionTemporarilyDisconnectTimer reset];
            [[Analytics getInstance] pushEventWithCategory:@"conversation" action:@"ended" label:@"network_disconnect"];
            break;

        case P_NOT_CONNECTED_HASH_REJECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected\nPrevious session timed out" showConversationEndView:false];

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

// Display view overlay showing how connection is being recovered.
- (void)setDisconnectStateWithShortDescription:(NSString *)shortDescription showConversationEndView:(bool)showConversationEndView {
    void (^block)() = ^{
        dispatch_sync_main(^{
            // Show the disconnect storyboard.
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];

            Boolean alreadyPresented = _disconnectViewController != nil;
            if (!alreadyPresented) {
                [self preprepareRuntimeView];

                _disconnectViewController = (AlertViewController *) [storyboard instantiateViewControllerWithIdentifier:@"DisconnectAlertView"];
                _disconnectViewController.view.frame = self.view.bounds;

                if (_hasHadAtLeastOneConversation) {
                    [_disconnectViewController enableAdverts];
                }

                __weak typeof(self) weakSelf = self;
                __weak AlertViewController *weakViewController;
                [_disconnectViewController setMoveToFacebookViewControllerFunc:^{
                    [weakSelf onGotoFbLogonViewButtonPress:weakViewController];
                }];

                if (_mediaController != nil) {
                    [_mediaController setLocalImageDelegate:_disconnectViewController];
                }

                [self addChildViewController:_disconnectViewController];
                [self.view addSubview:_disconnectViewController.view];
            } else {
                if (_mediaController != nil) {
                    [_mediaController setLocalImageDelegate:_disconnectViewController];
                }
            }
            // Set its content
            [_disconnectViewController setConversationEndedViewVisible:showConversationEndView instantly:true];
            [_disconnectViewController setAlertShortText:shortDescription];

            if (!alreadyPresented) {
                [_disconnectViewController didMoveToParentViewController:self];
                _waitingForNewEndPoint = true;
                [_mediaController stop];

                // Important so that we don't notify google analytics of screen change, whilst inside FB view.
                if (!_inFacebookLoginView) {
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
            [self setDisconnectStateWithShortDescription:@"Reconnecting to existing session\nThe other person disconnected temporarily" showConversationEndView:false];
        } else if (operation == DISCONNECT_PERM) {
            [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with\nThe other person left" showConversationEndView:true];
            NSLog(@"End point permanently disconnected");
        } else if (operation == DISCONNECT_SKIPPED) {
            [self setDisconnectStateWithShortDescription:@"Matching you with somebody to talk with\nThe other person skipped you" showConversationEndView:true];
            NSLog(@"End point skipped us");
        } else if (_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        // Waiting for server to match us with somebody new.
        if (_waitingForNewEndPoint) {
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


- (void)prepareTutorials {
    NSString *tutorialLastPreparedEpochSecondsKey = @"tutorialLastPreparedEpochSeconds";

    // Show the tutorial if not had the potential to do so (by running the app) for at least this long.
    const double tutorialInactivityFrequency = 86400 * 7; // 7 days.

    const NSUserDefaults *storage = [NSUserDefaults standardUserDefaults];
    const double storedEpochSeconds = [storage doubleForKey:tutorialLastPreparedEpochSecondsKey]; // returns 0 if not stored.
    const double currentEpochSeconds = [Timer getSecondsEpoch];
    const double difference = currentEpochSeconds - storedEpochSeconds;
    if (difference < tutorialInactivityFrequency || difference < 0) {
        NSLog(@"Time since last tutorial prepare is: %.0f seconds, not showing tutorial", difference);
        [storage setDouble:currentEpochSeconds forKey:tutorialLastPreparedEpochSecondsKey];
        return;
    }

    NSLog(@"Time since last tutorial prepare is: %.0f seconds, showing tutorial", difference);

    // Once per application run.
    float fadeInDuration = 1.0f;
    float fadeOutDuration = 2.0f;
    float delay = 3.0f;
    [ViewInteractions fadeInOut:_swipeTutorialSkip completion:^void(BOOL finishedSkip) {
        if (!finishedSkip || _disconnectViewController != nil) {
            return;
        }

        [ViewInteractions fadeInOut:_swipeTutorialChangeSettings completion:^void(BOOL finishedChangeSettings) {
            if (!finishedChangeSettings || _disconnectViewController != nil) {
                return;
            }

            // Update only after tutorial has completed successfully.
            [storage setDouble:currentEpochSeconds forKey:tutorialLastPreparedEpochSecondsKey];
        }                   options:UIViewAnimationOptionOverrideInheritedCurve | UIViewAnimationOptionOverrideInheritedDuration fadeInDuration:fadeInDuration fadeOutDuration:fadeOutDuration fadeOutDelay:delay];
    }                   options:UIViewAnimationOptionOverrideInheritedCurve | UIViewAnimationOptionOverrideInheritedDuration fadeInDuration:fadeInDuration fadeOutDuration:fadeOutDuration fadeOutDelay:delay];
}

- (void)preprepareRuntimeView {
    dispatch_sync_main(^{
        [_cameraView.layer removeAllAnimations];
        [_swipeTutorialSkip setAlpha:0.0f];
        [_swipeTutorialChangeSettings setAlpha:0.0f];
        [_ownerAge setAlpha:0.0f];
        [_ownerName setAlpha:0.0f];
        [_remoteAge setAlpha:0.0f];
        [_remoteName setAlpha:0.0f];
        [_cameraView setAlpha:0.0f];
        [_remoteDistance setAlpha:0.0f];
    });
}

- (void)prepareRuntimeView {
    [self prepareTutorials];

    [ViewInteractions fadeIn:_cameraView completion:nil duration:1.0f];

    [ViewInteractions fadeIn:_ownerName completion:^(BOOL completed) {
        if (!completed || _disconnectViewController != nil) {
            return;
        }

        [ViewInteractions fadeIn:_ownerAge completion:^(BOOL completedNext) {
            if (!completedNext || _disconnectViewController != nil) {
                return;
            }
            [ViewInteractions fadeIn:_remoteDistance completion:nil duration:2.0f];
        }               duration:2.0f];
    }               duration:2.0f];

    [ViewInteractions fadeIn:_remoteName completion:^(BOOL completed) {
        if (!completed || _disconnectViewController != nil) {
            return;
        }
        [ViewInteractions fadeIn:_remoteAge completion:nil duration:2.0f];
    }               duration:2.0f];
}

@end
