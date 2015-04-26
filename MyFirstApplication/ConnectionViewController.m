//
//  MyClass.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionViewController.h"
#import "MediaController.h"

@import AVFoundation;

@implementation ConnectionViewController {
    ConnectionManagerProtocol * _connection;
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    MediaController *_mediaController;
    bool _connected;
}

-(void)viewDidLoad {
    [super viewDidLoad];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    _connection = [[ConnectionManagerProtocol alloc] initWithRecvDelegate:self andConnectionStatusDelegate:self];
    _mediaController = [[MediaController alloc] initWithImageDelegate:self andwithNetworkOutputSession:[_connection getUdpOutputSession] ];
    [_mediaController startCapturing];
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
    static const int CONNECT_PORT_TCP = 12340;
    static const int CONNECT_PORT_UDP = 12341;
    [_connection shutdown];
    [_connection connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP udpHost:CONNECT_IP udpPort:CONNECT_PORT_UDP];
}

- (IBAction)onLocalConnectButtonClick:(id)sender {
    static NSString *const CONNECT_IP = @"192.168.1.92"; // local arden crescent network.
    static const int CONNECT_PORT_TCP = 12340;
    static const int CONNECT_PORT_UDP = 12341;
    [_connection shutdown];
    [_connection connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP udpHost:CONNECT_IP udpPort:CONNECT_PORT_UDP];
}

- (IBAction)onSendButtonClick:(id)sender {
    NSString * text = [_textToSend text];
    NSLog(@"Sending packet: %@", text);
    
    ByteBuffer * buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger: 0];
    [buffer addString: text];
    [_connection sendTcpPacket:buffer];
}

- (void) _doConnectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);
    [[self connectionStatus] setText: description];
    
    [_mediaController connectionStatusChange:status withDescription:description];
    
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
            [_connection shutdown];
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
    uint op = 1;//[packet getUnsignedInteger];
    if(op == 1) {
        [_mediaController onNewPacket:packet fromProtocol:UDP];
    } else {
        NSLog(@"Dropping unusual packet: %ul", op);
    }
}

@end
