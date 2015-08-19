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

@import AVFoundation;

@implementation ConnectionViewController {
    id<ConnectionGovernor> _connection;
    ConnectionCommander* _connectionCommander;
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    MediaController *_mediaController;
    bool _connected;
    IBOutlet UILabel *_frameRate;
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
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    
    [[SocialState getFacebookInstance] updateFacebook];
    if(![[SocialState getFacebookInstance] isDataLoaded]) {
        [self _switchToFacebookLogonView];
        return;
    }
    QuarkLogin* loginProvider = [[QuarkLogin alloc] init];
    
    
    _connectionCommander = [[ConnectionCommander alloc] initWithRecvDelegate:self connectionStatusDelegate:self slowNetworkDelegate:self governorSetupDelegate:self loginProvider:loginProvider];
    
    
    [[GpsState getInstance] update];
}

- (void)onNewImage: (UIImage*)image {
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

- (void)onNewGovernor:(id<ConnectionGovernor>)governor {
    _connection = governor;
    
    _mediaController = [[MediaController alloc] initWithImageDelegate:self videoSpeedNotifier:self tcpNetworkOutputSession:[_connection getTcpOutputSession] udpNetworkOutputSession:[_connection getUdpOutputSession]];
}

- (IBAction)onLocalConnectButtonClick:(id)sender {
    static NSString *const CONNECT_IP = @"192.168.1.92"; // local arden crescent network.
    static const int CONNECT_PORT_TCP = 12241;
    [_connectionCommander connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP];
}

- (void) _doConnectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);
    [[self connectionStatus] setText: description];
    
    if(_mediaController != nil) {
        [_mediaController connectionStatusChange:status withDescription:description];
    }
    
    switch(status) {
        case P_CONNECTING:
            [[self connectionStatus] setTextColor: [UIColor yellowColor]];
            [[self connectionStatus] setHidden:true];
            [[self connectionProgress] startAnimating];
            _connected = false;
            break;
            
        case P_CONNECTED:
            [[self connectionStatus] setTextColor: [UIColor greenColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            _connected = true;
            break;
        
        case P_NOT_CONNECTED:
            [[self connectionStatus] setTextColor: [UIColor redColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            _connected = false;
            break;
            
        default:
            NSLog(@"Bad connection state");
            [_connectionCommander shutdown];
            _connected = false;
            break;
    }
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    [[self connectionStatus] setNeedsDisplay];
    
    // So that sockets/streams are owned by main thread.
    if([NSThread isMainThread]) {
        [self _doConnectionStatusChange:status withDescription:description];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _doConnectionStatusChange:status withDescription:description];
        });
    }
}


- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if(_mediaController != nil) {
        [_mediaController onNewPacket:packet fromProtocol:protocol];
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
