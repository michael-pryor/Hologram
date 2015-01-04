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
#import "Encoding.h"
#import "MediaByteBuffer.h"
@import AVFoundation;

@implementation ConnectionViewController {
    ConnectionManager * _connection;
    IBOutlet UIImageView *_cameraView;
    AVCaptureSession *session;
    AVCaptureDeviceInput *input;
    AVCaptureVideoDataOutput *output;
    AVCaptureDevice *device;
    Encoding* _encoder;
}

- (id) init {
    self = [super init];
    if(self) {
        _outputSession = nil;
    }
    return self;
}

-(void)viewDidLoad {
    [super viewDidLoad];
}



-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    
    // setup session to receive data from input device.
    session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetMedium;
    
    // access input device.
    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    NSError *error = nil;
    input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        NSLog(@"Could not access input device: %@", error);
    }
    
    // add input device to session.
    [session addInput:input];
    
    // setup output session.
    output = [[AVCaptureVideoDataOutput alloc] init];
    [session addOutput:output];
    
    AVCaptureConnection *conn = [output connectionWithMediaType:AVMediaTypeVideo];
    [conn setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    output.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    
    // tell output session to use newly created queue, and push to captureOutput function.
    dispatch_queue_t queue = dispatch_queue_create("MyQueue", NULL);
    [output setSampleBufferDelegate:self queue:queue];
    [session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // update display.
    UIImage *image = [_encoder imageFromSampleBuffer: sampleBuffer];
    
    MediaByteBuffer* buffer = [[MediaByteBuffer alloc] init];
    [buffer addImage: sampleBuffer];
    
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
    if(_outputSession != nil) {
        NSLog(@"Closing existing connection..");
        [_outputSession closeConnection];
    }
    
    InputSessionTCP * sessionTcp = [[InputSessionTCP alloc] initWithDelegate: self];
    _outputSession = [[OutputSession alloc] init];
    _connection = [[ConnectionManager alloc] initWithDelegate: self inputSession: sessionTcp outputSession: _outputSession ];
    [_connection connect];
}

- (IBAction)onSendButtonClick:(id)sender {
    NSString * text = [_textToSend text];
    NSLog(@"Sending packet: %@", text);
    
    ByteBuffer * buffer = [[ByteBuffer alloc] init];
    [buffer addString:text];
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
    NSLog(@"New packet received: %@", [packet convertToString]);
}

@end
