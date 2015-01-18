//
//  MyClass.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionViewController.h"
#import "InputSession.h"
#import "OutputSession.h"
#import "MediaController.h"

@import AVFoundation;

typedef enum  {
    TEXT = 1,
    VISUAL = 2
} OperationType;

@implementation ConnectionViewController {
    ConnectionManager * _connection;
    ConnectionManagerUdp * _udpConnection;
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    MediaController *_mediaController;
    bool _stopProc;
    bool _connected;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    _outputSession = [[OutputSession alloc] init];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    _mediaController = [[MediaController alloc] initWithImageDelegate:self andwithNetworkOutputSession:_outputSession];
    [_mediaController startCapturing];
}

- (void)onNewImage: (UIImage*)image {
    [_cameraView performSelectorOnMainThread:@selector(setImage:) withObject: image waitUntilDone:YES];
}

- (IBAction)onSpecialButtonClick:(id)sender {
    self.view.backgroundColor = [UIColor yellowColor];
    self.theLabel.backgroundColor = [UIColor redColor];
    self.theLabel.text = @"Wow we have changed the colours!";
}

- (BOOL) textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (IBAction)onConnectButtonClick:(id)sender {
    // TCP SIDE
    /*if(_outputSession != nil && ![_outputSession isClosed]) {
        NSLog(@"Closing existing connection..");
        [_outputSession closeConnection];
    }*/
    
    NSString * theMagicalHash = @"MY HASH IS COOLER THAN YOURS";
    if([_outputSession isClosed]) {
    
    InputSessionTCP * sessionTcp = [[InputSessionTCP alloc] initWithDelegate: self];

    _connection = [[ConnectionManager alloc] initWithDelegate: self inputSession: sessionTcp outputSession: _outputSession ];
    [_connection connect];
    
    // UDP SIDE
    static NSString *const CONNECT_IP = @"192.168.1.92";
    static const int CONNECT_PORT = 12341;
    
    if(_udpConnection == nil) {
        _udpConnection = [[ConnectionManagerUdp alloc] init];
        [_udpConnection connectToHost:CONNECT_IP andPort:CONNECT_PORT];
    }
    
    ByteBuffer* theLogonBuffer = [[ByteBuffer alloc] init];
    [theLogonBuffer addUnsignedInteger:100];
    [theLogonBuffer addString:@"My name is Michael"];
    [theLogonBuffer addString:theMagicalHash];
    [_outputSession sendPacket:theLogonBuffer];

        ByteBuffer* theUdpLogonBuffer = [[ByteBuffer alloc] init];
        [theUdpLogonBuffer addString:theMagicalHash];
        [_udpConnection sendBuffer: theUdpLogonBuffer];
    }
    
    ByteBuffer* theUdpLogonBuffer = [[ByteBuffer alloc] init];
    [theUdpLogonBuffer addString:theMagicalHash];
    [_udpConnection sendBuffer: theUdpLogonBuffer];
    
    ByteBuffer* bbuffer = [[ByteBuffer alloc] init];
    [bbuffer addString:@"HELLO UNIVERSE!!!!"];
    [_udpConnection sendBuffer:bbuffer];
}

- (IBAction)onSendButtonClick:(id)sender {
    NSString * text = [_textToSend text];
    NSLog(@"Sending packet: %@", text);
    
    ByteBuffer * buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger: TEXT];
    [buffer addString: text];
    [_outputSession sendPacket:buffer];
}

- (void)connectionStatusChange:(ConnectionStatus)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);
    [[self connectionStatus] setText: description];
    
    switch(status) {
        case CONNECTING:
            [[self connectionStatus] setTextColor: [UIColor yellowColor]];
            [[self connectionStatus] setHidden:true];
            [[self connectionProgress] startAnimating];
            _connected = false;
            break;
            
        case OK_CON:
            [[self connectionStatus] setTextColor: [UIColor greenColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            _connected = true;
            break;
        
        case ERROR_CON:
            [[self connectionStatus] setTextColor: [UIColor redColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            _connected = false;
            break;
    }
}


- (void)onNewPacket:(ByteBuffer *)packet {
    uint op = [packet getUnsignedInteger];
    [_mediaController onNewPacket:packet];
}

@end
