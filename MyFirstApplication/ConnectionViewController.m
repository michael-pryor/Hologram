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
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    MediaController *_mediaController;
    bool _stopProc;
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
    if(_outputSession != nil && ![_outputSession isClosed]) {
        NSLog(@"Closing existing connection..");
        [_outputSession closeConnection];
    }
    
    InputSessionTCP * sessionTcp = [[InputSessionTCP alloc] initWithDelegate: self];

    _connection = [[ConnectionManager alloc] initWithDelegate: self inputSession: sessionTcp outputSession: _outputSession ];
    [_connection connect];
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
            break;
            
        case OK_CON:
            [[self connectionStatus] setTextColor: [UIColor greenColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            break;
        
        case ERROR_CON:
            [[self connectionStatus] setTextColor: [UIColor redColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            break;
    }
}


- (void)onNewPacket:(ByteBuffer *)packet {
    uint op = [packet getUnsignedInteger];
    [_mediaController onNewPacket:packet];
}

@end
