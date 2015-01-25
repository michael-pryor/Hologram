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
    _connection = [[ConnectionManagerProtocol alloc] initWithRecvDelegate:self andConnectionStatusDelegate:self];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    _mediaController = [[MediaController alloc] initWithImageDelegate:self andwithNetworkOutputSession:[_connection getTcpOutputSession]];
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
    // TCP SIDE
    static NSString *const CONNECT_IP = @"192.168.1.92";
    static const int CONNECT_PORT_TCP = 12340;
    static const int CONNECT_PORT_UDP = 12341;
    if(_connection != nil) {
        [_connection shutdown];
        [_connection connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP udpHost:CONNECT_IP udpPort:CONNECT_PORT_UDP];
    }
}

- (IBAction)onSendButtonClick:(id)sender {
    NSString * text = [_textToSend text];
    NSLog(@"Sending packet: %@", text);
    
    ByteBuffer * buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger: 0];
    [buffer addString: text];
    [_connection sendTcpPacket:buffer];
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);
    [[self connectionStatus] setText: description];
    
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
    }
}


- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint op = [packet getUnsignedInteger];
    [_mediaController onNewPacket:packet fromProtocol:protocol];
}

@end
