//
//  MyClass.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionViewController.h"
#import "MediaController.h"
#import "BatcherInput.h"
#import "BatcherOutput.h"

@import AVFoundation;

@implementation ConnectionViewController {
    ConnectionManagerProtocol * _connection;
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    MediaController *_mediaController;
    BatcherOutput *_batcherOutput;
    BatcherInput *_batcherInput;
    bool _connected;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    _batcherInput = [[BatcherInput alloc] initWithOutputSession:self chunkSize:1024 numChunks:80 andNumChunksThreshold:70 andTimeoutMs:1000];
    _connection = [[ConnectionManagerProtocol alloc] initWithRecvDelegate:_batcherInput andConnectionStatusDelegate:self];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:[_connection getUdpOutputSession] andChunkSize:1024];
    _mediaController = [[MediaController alloc] initWithImageDelegate:self andwithNetworkOutputSession:_batcherOutput];
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
    static NSString *const CONNECT_IP = @"192.168.1.92";
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

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
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


//- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
- (void)sendPacket: (ByteBuffer*)packet {
    uint op = [packet getUnsignedInteger];
    if(op == 1) {
        [_mediaController onNewPacket:packet fromProtocol:UDP];
    } else {
        NSLog(@"Dropping unusual packet: %ul", op);
    }
}

@end
