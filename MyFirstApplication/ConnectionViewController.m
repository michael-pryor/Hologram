//
//  MyClass.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionViewController.h"
#import "MediaController.h"
#import "ConnectionGovernorNatPunchthrough.h"
#import "ConnectionCommander.h"
#import "FacebookLoginViewController.h"
#import "SocialState.h"
#import "GpsState.h"
#import "QuarkLogin.h"
#import "Timer.h"
#import "AlertViewController.h"

@import AVFoundation;

@implementation ConnectionViewController {
    id<ConnectionGovernor> _connection;
    ConnectionCommander* _connectionCommander;
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    MediaController *_mediaController;
    bool _connected;
    IBOutlet UILabel *_frameRate;
    ByteBuffer* _skipPersonPacket;
    AlertViewController* _disconnectViewController;
    GpsState* _gpsState;
    IBOutlet UIProgressView *_connectionStrength;
}

- (void)_switchToFacebookLogonView {
    // We are the entry point, so we push to the Facebook view controller.
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    FacebookLoginViewController* viewController = (FacebookLoginViewController*)[storyboard instantiateViewControllerWithIdentifier:@"FacebookView"];
    UINavigationController* test = self.navigationController;
    [test pushViewController:viewController animated:YES];
}



- (IBAction)onFacebookButtonPress:(id)sender {
    [self _switchToFacebookLogonView];
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    _skipPersonPacket = [[ByteBuffer alloc] init];
    [_skipPersonPacket addUnsignedInteger:SKIP_PERSON];
}

- (void)onNatPunchthrough:(ConnectionGovernorNatPunchthrough*)connection stateChange:(NatState)state {
    if(state == ROUTED) {
        NSLog(@"Regressed to routing mode");
        _connectionStrength.progress = 0.5f;
    } else if(state == PUNCHED_THROUGH) {
        NSLog(@"Punched through successfully");
        _connectionStrength.progress = 1.0f;
    } else {
        NSLog(@"Unsupported punchthrough state received");
    }
}

-(void)onSocialDataLoaded:(SocialState*)state {
    [state unregisterNotifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        _gpsState = [[GpsState alloc] initWithNotifier:self];
        [_gpsState update];
        [self setDisconnectStateWithShortDescription:@"Loading GPS details" longDescription:@"Waiting for GPS information to load"];
    });
}

-(void)onDataLoaded:(GpsState*)state {
    QuarkLogin* loginProvider = [[QuarkLogin alloc] initWithGpsState:state];
    
    _connectionCommander = [[ConnectionCommander alloc] initWithRecvDelegate:self connectionStatusDelegate:self slowNetworkDelegate:self governorSetupDelegate:self loginProvider:loginProvider punchthroughNotifier:self];
    
    [self onLocalConnectButtonClick:0];
}
-(void)onFailure:(GpsState*)state withDescription:(NSString*)description {
    [self setDisconnectStateWithShortDescription:@"Failed to load GPS details" longDescription:description];
    
    // Try again in 2 seconds time.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [state update];
        [self setDisconnectStateWithShortDescription:@"Loading GPS details" longDescription:@"Waiting for GPS information to load"];
    });
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    
    if (_connectionCommander != nil) {
        [_connectionCommander terminate];
    }
    
    SocialState *socialState = [SocialState getFacebookInstance];
    [socialState updateFacebook];
    if(![socialState isBasicDataLoaded]) {
        [self _switchToFacebookLogonView];
        return;
    }
    if(![socialState isDataLoaded]) {
        [socialState registerNotifier:self];
        
        [self setDisconnectStateWithShortDescription:@"Loading Facebook details" longDescription:@"Waiting for Facebook details to load"];
        [socialState update];
    } else {
        [self onSocialDataLoaded:socialState];
    }
}

- (void)onNewImage: (UIImage*)image {
    if(_disconnectViewController != nil && ![_disconnectViewController hideIfVisibleAndReady]) {
        return;
    }
    _disconnectViewController = nil;
    
    [_cameraView performSelectorOnMainThread:@selector(setImage:) withObject: image waitUntilDone:YES];
    
}

- (BOOL) textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (IBAction)onConnectButtonClick:(id)sender {
    static NSString *const CONNECT_IP = @"212.227.84.229"; // remote machine (paid hosting).
    static const int CONNECT_PORT_TCP = 12241;
    [_connectionCommander connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP];
}

- (IBAction)showGestureForSwipeRecognizer:(UISwipeGestureRecognizer *)recognizer {
    if(recognizer.direction == UISwipeGestureRecognizerDirectionLeft) {
        NSLog(@"Sending skip request");
        [_connection sendTcpPacket:_skipPersonPacket];
        [self setDisconnectStateWithShortDescription:@"Skipped - finding new acquaintance" longDescription:@"Searching for somebody else suitable for you to talk with"];
    } else {
        [_connectionCommander terminate];
        [self _switchToFacebookLogonView];
    }
}

- (void)onNewGovernor:(id<ConnectionGovernor>)governor {
    if(_connection != nil) {
        [_connection terminate];
    }
    _connection = governor;
    
    if(_mediaController != nil) {
        [_mediaController setNetworkOutputSessionTcp:[_connection getTcpOutputSession] Udp:[_connection getUdpOutputSession]];
    } else {
        _mediaController = [[MediaController alloc] initWithImageDelegate:self videoSpeedNotifier:self tcpNetworkOutputSession:[_connection getTcpOutputSession] udpNetworkOutputSession:[_connection getUdpOutputSession]];
    }
}

- (IBAction)onLocalConnectButtonClick:(id)sender {
    static NSString *const CONNECT_IP = @"192.168.1.92"; // local arden crescent network.
    static const int CONNECT_PORT_TCP = 12241;
    [_connectionCommander connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP];
}

- (void) _doConnectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);
    
    if(_mediaController != nil) {
        [_mediaController connectionStatusChange:status withDescription:description];
    }
    
    switch(status) {
        case P_CONNECTING:
            _connected = false;
            [self setDisconnectStateWithShortDescription:@"Connecting" longDescription:description];
            break;
            
        case P_CONNECTED:
            _connected = true;
            [self setDisconnectStateWithShortDescription:@"Finding acquaintance" longDescription:@"Searching for somebody suitable for you to talk with"];
            break;
        
        case P_NOT_CONNECTED:
            _connected = false;
            [self setDisconnectStateWithShortDescription:@"Connection failure" longDescription:description];
            break;
            
        default:
            NSLog(@"Bad connection state");
            [_connectionCommander shutdown];
            _connected = false;
            break;
    }
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    // So that sockets/streams are owned by main thread.
    if([NSThread isMainThread]) {
        [self _doConnectionStatusChange:status withDescription:description];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _doConnectionStatusChange:status withDescription:description];
        });
    }
}


-(void)setDisconnectStateWithShortDescription:(NSString*)shortDescription longDescription:(NSString*)longDescription{
    
    // Show the disconnect storyboard.
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    
    Boolean alreadyPresented = _disconnectViewController != nil;
    if(!alreadyPresented) {
        _disconnectViewController = (AlertViewController*)[storyboard instantiateViewControllerWithIdentifier:@"DisconnectAlertView"];
    
        [self addChildViewController: _disconnectViewController];
        [self.view addSubview:_disconnectViewController.view];
    }
    // Set its content
    [_disconnectViewController setAlertShortText:shortDescription longText:longDescription];

    if(!alreadyPresented) {
        [_disconnectViewController didMoveToParentViewController: self];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if(protocol == TCP) {
        uint operation = [packet getUnsignedIntegerAtPosition:0];
        if(operation == DISCONNECT_TEMP) {
            NSLog(@"End point temporarily disconnected");
            [self setDisconnectStateWithShortDescription:@"Acquaintance disconnected temporarily" longDescription:@"The person you were talking with has temporarily disconnected, please wait a few seconds to see if they can rejoin!"];
        } else if(operation == DISCONNECT_PERM) {
            [self setDisconnectStateWithShortDescription:@"Acquaintance permanently disconnected"  longDescription:@"The person you were talking with has permanently disconnected, we'll find you someone else to talk to"];
            NSLog(@"End point permanently disconnected");
        } else if(operation == DISCONNECT_SKIPPED) {
            [self setDisconnectStateWithShortDescription:@"Acquaintance skipped you" longDescription:@"The person you were talking with skipped you, we'll find you someone else to talk to"];
            NSLog(@"End point skipped us");
        } else if(_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        if(_mediaController != nil) {
            [_mediaController onNewPacket:packet fromProtocol:protocol];
        }
    }
}

- (void)onNewVideoFrameFrequency:(CFAbsoluteTime)secondsFrequency {
    CFAbsoluteTime frameRate = 1.0 / secondsFrequency;
    [_frameRate setText:[NSString stringWithFormat:@"%.2f", frameRate]];
}

- (void)slowNetworkNotification {
    if(_mediaController != nil) {
        [_mediaController sendSlowdownRequest];
    }
}
@end
