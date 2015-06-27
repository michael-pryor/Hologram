//
//  ConnectionManagerProtocolWithNatPunchtrough.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/06/2015.
//
//

#import "ConnectionGovernorNatPunchthrough.h"

@implementation ConnectionGovernorNatPunchthrough {
    ConnectionManagerUdp* _udpNatPunchthroughConnection;
    
}
- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate {
    self = [super initWithRecvDelegate:recvDelegate connectionStatusDelegate:connectionStatusDelegate slowNetworkDelegate:slowNetworkDelegate];
    if(self) {
        _udpNatPunchthroughConnection = [[ConnectionManagerUdp alloc] initWithNewPacketDelegate:self slowNetworkDelegate:slowNetworkDelegate connectionDelegate:self retryCount:5];
    }
    return self;
}

- (void)sendUdpPacket:(ByteBuffer*)packet {
    
}
@end
