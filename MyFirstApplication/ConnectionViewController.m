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
}

// View initially load; happens once per process.
// Essentially this is the constructor.
- (void)viewDidLoad {
    [super viewDidLoad];

    _screenName = @"VideoChat";
    _connectionStateTimer = [[Timer alloc] init];
    _connectingNetworkTimer = [[Timer alloc] init];
    _connectionTemporarilyDisconnectTimer = [[Timer alloc] init];

    _inFacebookLoginView = false;
    _isSkippableDespiteNoMatch = false;

    [self setDisconnectStateWithShortDescription:@"Initializing" longDescription:@"Initializing media controller"];

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

    _gpsState = [[GpsState alloc] initWithNotifier:self];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillRetakeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
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
    [self terminateCurrentSession];
}

// Doesn't terminate the session, remains connected but pauses media input/output
// Once reconnecting, this resumes and hopefully we're still connected (if not we recover
// down the usual disconnection logic).
- (void)appWillResignActive:(NSNotification *)note {
    [_mediaController stop];
}

- (void)appWillRetakeActive:(NSNotification *)note {
    [_mediaController start];
}

// View appears; happens if user switches app or moves from a different view controller.
//
// Update state; if facebook information not loaded, move to facebook view controller.
// Start by loading facebook information, then do GPS and then start connection to commander.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Start off in routed mode.
    previousState = ROUTED;
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

    [_accessDialog validateAuthorization:^{
        // This step can take a few seconds (particularly on older devices).
        [self setDisconnectStateWithShortDescription:@"Initializing" longDescription:@"Initializing media controller"];
        if (_mediaController == nil) {
            _mediaController = [[MediaController alloc] initWithImageDelegate:self mediaDataLossNotifier:self];
        }
        [_mediaController startVideo];

        if (![socialState isDataLoaded]) {
            [socialState registerNotifier:self];
            [self setDisconnectStateWithShortDescription:@"Loading Facebook details" longDescription:@"Waiting for Facebook details to load"];
            if (![socialState updateGraphFacebookInformation]) {
                [self switchToFacebookLogonView];
            }
        } else {
            [self onSocialDataLoaded:socialState];
        }
    }];
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

        [_gpsState update];
        [self setDisconnectStateWithShortDescription:@"Loading GPS details" longDescription:@"Waiting for GPS information to load"];
    });
}

// Callback for GPS data.
// Starts connection.
- (void)onGpsDataLoaded:(GpsState *)state {
    HologramLogin *loginProvider = [[HologramLogin alloc] initWithGpsState:state];
    _connectionCommander = [[ConnectionCommander alloc] initWithRecvDelegate:self connectionStatusDelegate:self governorSetupDelegate:self loginProvider:loginProvider punchthroughNotifier:self];
    [self connectToCommander];
}

// Connect to the remote server.
- (void)connectToRemoteCommander {
    static NSString *const CONNECT_IP = @"212.227.84.229"; // remote machine (paid hosting).
    static const int CONNECT_PORT_TCP = 12241;
    [_connectionCommander connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP];
    _isConnectionActive = true;
}

// Connect to the local server (on same network).
- (void)connectToLocalCommander {
    static NSString *const CONNECT_IP = @"192.168.1.92"; // local arden crescent network.
    static const int CONNECT_PORT_TCP = 12241;
    [_connectionCommander connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP];
    _isConnectionActive = true;
}

- (void)connectToCommander {
    [self connectToLocalCommander];
}

// On failure retrieving GPS failure, retry every 2 seconds.
- (void)onGpsDataLoadFailure:(GpsState *)state withDescription:(NSString *)description {
    [self setDisconnectStateWithShortDescription:@"Failed to load GPS details, retrying" longDescription:description];

    // Try again in 2 seconds time.
    // Note this is just updating the UI. After failure, GPS automatically keeps retrying so needs
    // no further calls. But after two seconds we want the user to feel like we are doing something if
    // the situation hasn't improved.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![state isLoaded]) {
            [self setDisconnectStateWithShortDescription:@"Loading GPS details" longDescription:@"Waiting for GPS information to load"];
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
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"conversation_duration" name:@"via_server" label:@"routing"];
            } else if (previousStateLocal == PUNCHED_THROUGH) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"conversation_duration" name:@"peer_to_peer" label:@"routing"];
            }

            // Time it took to punch through NAT and establish peer to peer connection.
            if (previousStateLocal == ADDRESS_RECEIVED && state == PUNCHED_THROUGH) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"setup_duration" name:@"punch_through" label:@"routing"];
            }

            // Total time spent in conversation.
            if ((previousStateLocal == ADDRESS_RECEIVED || previousStateLocal == PUNCHED_THROUGH) && state == ROUTED) {
                [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"conversation_duration" name:@"duration" label:@"total"];
            }
        } else {
            // Time it took to complete matching process on server side.
            // In theory, can only be ROUTED prior to this, but shouldn't matter either way.
            // If server sends us an address, then we need to interact with the client at that address.
            [[Analytics getInstance] pushTimingSeconds:secondsTimed withCategory:@"setup_duration" name:@"finding_match"];
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
            }
        }
        [_cameraView setImage:image];
    });
}

// User swiped right -> skip person.
// User swiped left <- goto facebook view controller.
- (IBAction)showGestureForSwipeRecognizer:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft) {
        if (_waitingForNewEndPoint && !_isSkippableDespiteNoMatch) {
            NSLog(@"Ignoring skip request, nobody to skip");
            return;
        }

        _isSkippableDespiteNoMatch = false;

        [[Analytics getInstance] pushEventWithCategory:@"conversation_ending" action:@"skip" label:@"initiated"];

        NSLog(@"Sending skip request");
        [_connection sendTcpPacket:_skipPersonPacket];
        [self setDisconnectStateWithShortDescription:@"Connecting to new session\nYou skipped the other person" longDescription:@"Searching for somebody else suitable for you to talk with"];
    } else {
        [[Analytics getInstance] pushEventWithCategory:@"conversation_ending" action:@"facebook_screen"];
        [self switchToFacebookLogonView];
    }
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
            [self setDisconnectStateWithShortDescription:@"Connecting" longDescription:description];
            [_connectingNetworkTimer reset];
            break;

        case P_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Connecting to new session" longDescription:@"Searching for somebody suitable for you to talk with"];
            if (_mediaController != nil) {
                [_mediaController resetSendRate];
            }
            [[Analytics getInstance] pushTimer:_connectingNetworkTimer withCategory:@"setup_duration" name:@"network_connecting" label:@"new_session"];
            break;

        case P_CONNECTED_TO_EXISTING:
            [self setDisconnectStateWithShortDescription:@"Reconnected to existing session" longDescription:@"Resuming previous conversation or finding a new match"];
            [[Analytics getInstance] pushTimer:_connectingNetworkTimer withCategory:@"setup_duration" name:@"network_connecting" label:@"resumed_session"];

            // How long were we disconnected for?
            [[Analytics getInstance] pushTimer:_connectionTemporarilyDisconnectTimer withCategory:@"conversation_duration" name:@"disconnected" label:@"routing"];
            break;

        case P_NOT_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected" longDescription:description];
            [_connectionTemporarilyDisconnectTimer reset];
            [[Analytics getInstance] pushEventWithCategory:@"conversation_ending" action:@"network_disconnect"];
            break;

        case P_NOT_CONNECTED_HASH_REJECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected\nPrevious session timed out" longDescription:description];
            [self connectToCommander];
            break;

        default:
            NSLog(@"Bad connection state");
            [_connectionCommander shutdown];
            break;
    }
}

// Display view overlay showing how connection is being recovered.
- (void)setDisconnectStateWithShortDescription:(NSString *)shortDescription longDescription:(NSString *)longDescription {
    void (^block)() = ^{
        dispatch_sync_main(^{
            // Show the disconnect storyboard.
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];

            Boolean alreadyPresented = _disconnectViewController != nil;
            if (!alreadyPresented) {
                [self preprepareRuntimeView];

                _disconnectViewController = (AlertViewController *) [storyboard instantiateViewControllerWithIdentifier:@"DisconnectAlertView"];
                _disconnectViewController.view.frame = self.view.bounds;
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
            NSLog(@"Disconnect screen presented, long description: %@", longDescription);
            [_disconnectViewController setAlertShortText:shortDescription longText:longDescription];

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
            [self setDisconnectStateWithShortDescription:@"Reconnecting to existing session\nThe other person disconnected temporarily" longDescription:@"The person you were talking with has temporarily disconnected, please wait a few seconds to see if they can rejoin!"];
        } else if (operation == DISCONNECT_PERM) {
            [self setDisconnectStateWithShortDescription:@"Connecting to new session\nThe other person left" longDescription:@"The person you were talking with has permanently disconnected, we'll find you someone else to talk to"];
            NSLog(@"End point permanently disconnected");
        } else if (operation == DISCONNECT_SKIPPED) {
            [self setDisconnectStateWithShortDescription:@"Connecting to new session\nThe other person skipped you" longDescription:@"The person you were talking with skipped you, we'll find you someone else to talk to"];
            NSLog(@"End point skipped us");
        } else if (_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        // Waiting for server to match us with somebody new.
        if (_waitingForNewEndPoint) {
            return;
        }

        if (_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    }
}

- (void)onMediaDataLossFromSender:(MediaType)mediaType {
    dispatch_sync_main(^{
        if (mediaType == VIDEO) {
            NSLog(@"Data loss for video!");
            [ViewInteractions fadeInOut:_dcVideo completion:nil options:UIViewAnimationOptionBeginFromCurrentState];
            [[Analytics getInstance] pushEventWithCategory:@"network_jitter" action:@"video_loss"];
        } else if (mediaType == AUDIO) {
            NSLog(@"Data loss for audio!");
            [ViewInteractions fadeInOut:_dcAudio completion:nil options:UIViewAnimationOptionBeginFromCurrentState];
            [[Analytics getInstance] pushEventWithCategory:@"network_jitter" action:@"audio_loss"];
        } else if (mediaType == AUDIO_QUEUE_RESET) {
            NSLog(@"Extreme audio data loss (audio queue reset)!");
            [ViewInteractions fadeInOut:_dcAudioClear completion:nil options:UIViewAnimationOptionBeginFromCurrentState];
            [[Analytics getInstance] pushEventWithCategory:@"network_jitter" action:@"audio_reset"];
        } else {
            NSLog(@"Unknown data loss type");
        }
    });
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
    [ViewInteractions fadeInOut:_swipeTutorialSkip completion:^void(BOOL finishedSkip) {
        if (!finishedSkip) {
            return;
        }

        [ViewInteractions fadeInOut:_swipeTutorialChangeSettings completion:^void(BOOL finishedChangeSettings) {
            if (!finishedChangeSettings) {
                return;
            }

            // Update only after tutorial has completed successfully.
            [storage setDouble:currentEpochSeconds forKey:tutorialLastPreparedEpochSecondsKey];
        }                   options:UIViewAnimationOptionOverrideInheritedCurve | UIViewAnimationOptionOverrideInheritedDuration];
    }                   options:UIViewAnimationOptionOverrideInheritedCurve | UIViewAnimationOptionOverrideInheritedDuration];
}

- (void)preprepareRuntimeView {
    [_swipeTutorialSkip setAlpha:0.0f];
    [_swipeTutorialChangeSettings setAlpha:0.0f];
    [_ownerAge setAlpha:0.0f];
    [_ownerName setAlpha:0.0f];
    [_remoteAge setAlpha:0.0f];
    [_remoteName setAlpha:0.0f];
    [_cameraView setAlpha:0.0f];
    [_remoteDistance setAlpha:0.0f];
}

- (void)prepareRuntimeView {
    [self prepareTutorials];

    [ViewInteractions fadeIn:_cameraView completion:nil duration:4.0f];

    [ViewInteractions fadeIn:_ownerName completion:^(BOOL completed) {
        [ViewInteractions fadeIn:_ownerAge completion:^(BOOL completed) {
            [ViewInteractions fadeIn:_remoteDistance completion:nil duration:2.0f];
        }               duration:2.0f];
    }               duration:2.0f];

    [ViewInteractions fadeIn:_remoteName completion:^(BOOL completed) {
        [ViewInteractions fadeIn:_remoteAge completion:nil duration:2.0f];
    }               duration:2.0f];
}
@end
