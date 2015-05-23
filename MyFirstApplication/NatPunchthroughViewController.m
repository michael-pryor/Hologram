//
//  NatPunchthroughViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 16/05/2015.
//
//

#import "NatPunchthroughViewController.h"
#import <UIKit/UIViewController.h>
@import AVFoundation;

@implementation NatPunchthroughViewController {
    ConnectionManagerProtocol * _connection;
    bool _connected;
}

-(void)viewDidLoad {
    [super viewDidLoad];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    _connection = [[ConnectionManagerProtocol alloc] initWithRecvDelegate:self andConnectionStatusDelegate:self];
}

- (IBAction)onConnectButtonClick:(id)sender {
    static NSString *const CONNECT_IP = @"212.227.84.229"; // remote machine (paid hosting).
    static const int CONNECT_PORT_TCP = 12340;
    static const int CONNECT_PORT_UDP = 12341;
    [_connection shutdown];
    [_connection connectToTcpHost:CONNECT_IP tcpPort:CONNECT_PORT_TCP udpHost:CONNECT_IP udpPort:CONNECT_PORT_UDP];
}

- (void) connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
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
            
        default:
            NSLog(@"Bad connection state");
            [_connection shutdown];
            _connected = false;
            break;
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    NSLog(@"New packet received %@", packet);
}


@end
