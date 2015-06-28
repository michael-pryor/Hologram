//
//  ConnectionGovernor.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 28/06/2015.
//
//

#import "ConnectionGovernor.h"

@implementation ConnectionGovernorProtocolTcpSession {
    id<ConnectionGovernor> _connectionManager;
}
- (id)initWithConnectionManager: (id<ConnectionGovernor>)connectionGovernor {
    self = [super init];
    if(self) {
        _connectionManager = connectionGovernor;
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    // Drop until we are connected.
    if(![_connectionManager isConnected]) {
        return;
    }
    [_connectionManager sendTcpPacket:packet];
}
@end

@implementation ConnectionGovernorProtocolUdpSession {
    id<ConnectionGovernor> _connectionManager;
}
- (id)initWithConnectionManager:(id<ConnectionGovernor>)connectionGovernor {
    self = [super init];
    if(self) {
        _connectionManager = connectionGovernor;
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    // Drop until we are connected.
    if(![_connectionManager isConnected]) {
        return;
    }
    [_connectionManager sendUdpPacket:packet];
}
@end