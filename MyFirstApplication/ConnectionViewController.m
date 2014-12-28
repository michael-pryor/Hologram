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

@implementation ConnectionViewController
ConnectionManager * con;
OutputSession * outputSession;

-(void)viewDidLoad {
    [super viewDidLoad];
}
- (IBAction)onSpecialButtonClick:(id)sender {
    self.view.backgroundColor = [UIColor yellowColor];
    self.theLabel.backgroundColor = [UIColor redColor];
    self.theLabel.text = @"Wow we have changed the colours!";
}

- (IBAction)onConnectButtonClick:(id)sender {
    InputSessionTCP * sessionTcp = [[InputSessionTCP alloc] initWithDelegate: self];
    outputSession = [[OutputSession alloc] init];
    con = [[ConnectionManager alloc] initWithDelegate: self inputSession: sessionTcp outputSession: outputSession ];
    [con connect];
}

- (IBAction)onSendButtonClick:(id)sender {
    NSString * text = [_textToSend text];
    NSLog(@"Text %@", text);
    
    ByteBuffer * buffer = [[ByteBuffer alloc] init];
    [buffer addString:text];
    [outputSession sendPacket:buffer];
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
