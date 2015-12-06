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
#import "QuarkLogin.h"
#import "AlertViewController.h"

@implementation ConnectionViewController {
    // Connection
    id <ConnectionGovernor> _connection;
    ConnectionCommander *_connectionCommander;

    // Audio/Video
    MediaController *_mediaController;

    // GPS
    GpsState *_gpsState;

    // UI
    AlertViewController *_disconnectViewController;
    IBOutlet UIImageView *_cameraView;
    IBOutlet UILabel *_frameRate;
    IBOutlet UIView *_natPunchtrhoughIndicator;

    // State
    bool _waitingForNewEndPoint;
    bool _isConnectionActive;

    // Packets
    ByteBuffer *_skipPersonPacket;
    ByteBuffer *_permDisconnectPacket;

    bool _inFacebookLoginView;
}

// View initially load; happens once per process.
// Essentially this is the constructor.
- (void)viewDidLoad {
    [super viewDidLoad];

    _skipPersonPacket = [[ByteBuffer alloc] init];
    [_skipPersonPacket addUnsignedInteger:SKIP_PERSON];

    _permDisconnectPacket = [[ByteBuffer alloc] init];
    [_permDisconnectPacket addUnsignedInteger:DISCONNECT_PERM];

    _waitingForNewEndPoint = true;
    _isConnectionActive = false;

    _gpsState = [[GpsState alloc] initWithNotifier:self];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillRetakeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

// View disappears; happens if user switches app or moves from a different view controller.
- (void)viewDidDisappear:(BOOL)animated {
    // Notify server that we want to fully disconnect; server will close connection when it receives
    // notification. This prevents end point from thinking this could be a temporary disconnect.
    if (_connection != nil && _isConnectionActive) {
        [_connection disableReconnecting];
        [_connection sendTcpPacket:_permDisconnectPacket];
    }

    // Don't push anything to the display, might get a few lingering packets received after this point.
    _isConnectionActive = false;

    // Terminate microphone and video.
    [_mediaController stop];
}

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

    _inFacebookLoginView = false;

    SocialState *socialState = [SocialState getFacebookInstance];
    [socialState updateFacebook];
    if (![socialState isBasicDataLoaded]) {
        [self switchToFacebookLogonView];
        return;
    }
    if (![socialState isDataLoaded]) {
        [socialState registerNotifier:self];

        [self setDisconnectStateWithShortDescription:@"Loading Facebook details" longDescription:@"Waiting for Facebook details to load"];
        [socialState update];
    } else {
        [self onSocialDataLoaded:socialState];
    }
}

// Callback for social data (Facebook).
// Triggers GPS loading.
- (void)onSocialDataLoaded:(SocialState *)state {
    [state unregisterNotifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_gpsState update];
        [self setDisconnectStateWithShortDescription:@"Loading GPS details" longDescription:@"Waiting for GPS information to load"];
    });
}

// Callback for GPS data.
// Starts connection.
- (void)onGpsDataLoaded:(GpsState *)state {
    QuarkLogin *loginProvider = [[QuarkLogin alloc] initWithGpsState:state];

    _connectionCommander = [[ConnectionCommander alloc] initWithRecvDelegate:self connectionStatusDelegate:self slowNetworkDelegate:self governorSetupDelegate:self loginProvider:loginProvider punchthroughNotifier:self];

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
    [self setDisconnectStateWithShortDescription:@"Failed to load GPS details" longDescription:description];

    // Try again in 2 seconds time.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [state update];
        [self setDisconnectStateWithShortDescription:@"Loading GPS details" longDescription:@"Waiting for GPS information to load"];
    });
}


// Switch to the facebook logon view controller.
- (void)switchToFacebookLogonView {
    // We are the entry point, so we push to the Facebook view controller.
    if(_inFacebookLoginView) {
        return;
    }

    _inFacebookLoginView = true;
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    FacebookLoginViewController *viewController = (FacebookLoginViewController *) [storyboard instantiateViewControllerWithIdentifier:@"FacebookView"];
    [self.navigationController pushViewController:viewController animated:YES];
}

// Called when we receive a change in connection state regarding NAT punchthrough.
// Important to update the display so that we know how we are connected.
- (void)onNatPunchthrough:(ConnectionGovernorNatPunchthrough *)connection stateChange:(NatState)state {
    if (state == ROUTED) {
        NSLog(@"Regressed to routing mode");
        dispatch_async(dispatch_get_main_queue(), ^{
            [_natPunchtrhoughIndicator setBackgroundColor:[UIColor blueColor]
             ];
        });
    } else if (state == PUNCHED_THROUGH) {
        NSLog(@"Punched through successfully");
        dispatch_async(dispatch_get_main_queue(), ^{
[_natPunchtrhoughIndicator setBackgroundColor:[UIColor greenColor]];
        });
    } else if (state == ADDRESS_RECEIVED) {
        NSLog(@"New end point received");
        _waitingForNewEndPoint = false;
        [_mediaController start];
    } else {
        NSLog(@"Unsupported punchthrough state received");
    }
}


// Received a new image from network.
// Update the UI.
- (void)onNewImage:(UIImage *)image {
    if (_disconnectViewController != nil) {
        return;
    }

    [_cameraView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:YES];
}

// User swiped right -> skip person.
// User swiped left <- goto facebook view controller.
- (IBAction)showGestureForSwipeRecognizer:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft) {
        NSLog(@"Sending skip request");
        [_connection sendTcpPacket:_skipPersonPacket];
        [self setDisconnectStateWithShortDescription:@"Skipped, connecting to new session" longDescription:@"Searching for somebody else suitable for you to talk with"];
    } else {
        [self switchToFacebookLogonView];
    }
}

// Received server details from commander and have connected.
- (void)onNewGovernor:(id <ConnectionGovernor>)governor {
    if (_connection != nil) {
        [_connection terminate];
    }
    _connection = governor;

    if (_mediaController != nil) {
        [_mediaController setNetworkOutputSessionTcp:[_connection getTcpOutputSession] Udp:[_connection getUdpOutputSession]];
    } else {
        _mediaController = [[MediaController alloc] initWithImageDelegate:self videoSpeedNotifier:self tcpNetworkOutputSession:[_connection getTcpOutputSession] udpNetworkOutputSession:[_connection getUdpOutputSession] mediaDelayNotifier:self];
    }
    [_mediaController start];
}

// Handle change in connection state.
- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);

    switch (status) {
        case P_CONNECTING:
            [self setDisconnectStateWithShortDescription:@"Connecting" longDescription:description];
            break;

        case P_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Connecting to new session" longDescription:@"Searching for somebody suitable for you to talk with"];
            if (_mediaController != nil) {
                [_mediaController resetSendRate];
            }
            break;

        case P_CONNECTED_TO_EXISTING:
            [self setDisconnectStateWithShortDescription:@"Reconnected to existing session" longDescription:@"Resuming previous conversation or finding a new match"];
            break;

        case P_NOT_CONNECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected" longDescription:description];
            break;

        case P_NOT_CONNECTED_HASH_REJECTED:
            [self setDisconnectStateWithShortDescription:@"Disconnected" longDescription:description];
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

    // Show the disconnect storyboard.
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];

    Boolean alreadyPresented = _disconnectViewController != nil;
    if (!alreadyPresented) {
        _disconnectViewController = (AlertViewController *) [storyboard instantiateViewControllerWithIdentifier:@"DisconnectAlertView"];

        [self addChildViewController:_disconnectViewController];
        [self.view addSubview:_disconnectViewController.view];
    }
    // Set its content
    [_disconnectViewController setAlertShortText:shortDescription longText:longDescription];

    if (!alreadyPresented) {
        [_disconnectViewController didMoveToParentViewController:self];
        _waitingForNewEndPoint = true;
        [_mediaController stop];
    }
}

// Handle data and pass to relevant parts of application.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (!_isConnectionActive) {
        return;
    }

    if (protocol == TCP) {
        uint operation = [packet getUnsignedIntegerAtPosition:0];
        if (operation == DISCONNECT_TEMP) {
            NSLog(@"End point temporarily disconnected");
            [self setDisconnectStateWithShortDescription:@"Reconnecting to existing session" longDescription:@"The person you were talking with has temporarily disconnected, please wait a few seconds to see if they can rejoin!"];
        } else if (operation == DISCONNECT_PERM) {
            [self setDisconnectStateWithShortDescription:@"Connecting to new session" longDescription:@"The person you were talking with has permanently disconnected, we'll find you someone else to talk to"];
            NSLog(@"End point permanently disconnected");
        } else if (operation == DISCONNECT_SKIPPED) {
            [self setDisconnectStateWithShortDescription:@"Skipped, connecting to new session" longDescription:@"The person you were talking with skipped you, we'll find you someone else to talk to"];
            NSLog(@"End point skipped us");
        } else if (_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        if (_disconnectViewController != nil) {
            // Waiting for server to match us with somebody new.
            if (_waitingForNewEndPoint) {
                return;
            }

            if (![_disconnectViewController hideIfVisibleAndReady]) {
                return;
            } else {
                _disconnectViewController = nil;
            }
        }

        if (_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    }
}

// Notification that video frame rate has changed.
- (void)onNewVideoFrameFrequency:(CFAbsoluteTime)secondsFrequency {
    // Do nothing with this information.
}

- (void)onMediaDelayNotified:(uint)delayMs {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_frameRate setText:[NSString stringWithFormat:@"%d", delayMs]];
    });
}

// Received request to slow down video send rate.
- (void)slowNetworkNotification {
    if (_mediaController != nil) {
        [_mediaController sendSlowdownRequest];
    }
}
@end
