//
//  ConnectionManagerProtocolWithNatPunchtrough.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/06/2015.
//
//

#import "ConnectionGovernorNatPunchthrough.h"
#import "ConnectionGovernorProtocol.h"
#import "NetworkOperations.h"
#import "Timer.h"

@implementation ConnectionGovernorNatPunchthrough {
    ConnectionGovernorProtocol* _connectionGovernor;
    id<NewPacketDelegate> _recvDelegate;
    uint _punchthroughAddress;
    uint _punchthroughPort;
    Boolean _routeThroughPunchthroughAddress;
    Timer* _natPunchthroughDiscoveryTimer;
    ByteBuffer* _natPunchthroughDiscoveryPacket;
}
- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate {
    if(self) {
        _recvDelegate = recvDelegate;
        _connectionGovernor = [[ConnectionGovernorProtocol alloc] initWithRecvDelegate:self unknownRecvDelegate:self connectionStatusDelegate:connectionStatusDelegate slowNetworkDelegate:slowNetworkDelegate];
        
        _punchthroughAddress = 0;
        _punchthroughPort = 0;
        _routeThroughPunchthroughAddress = false;
        _natPunchthroughDiscoveryTimer = [[Timer alloc] initWithFrequencySeconds:5 firingInitially:true];
        
        _natPunchthroughDiscoveryPacket = [[ByteBuffer alloc] initWithSize:sizeof(uint)];
        [_natPunchthroughDiscoveryPacket addUnsignedInteger:NAT_PUNCHTHROUGH_DISCOVERY];
    }
    return self;
}

- (Boolean)isConnected {
    return [_connectionGovernor isConnected];
}

- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort {
    [_connectionGovernor connectToTcpHost:tcpHost tcpPort:tcpPort udpHost:udpHost udpPort:udpPort];
}
- (void)sendTcpPacket:(ByteBuffer*)packet {
    [_connectionGovernor sendTcpPacket:packet];
}
- (void)sendUdpPacket:(ByteBuffer*)packet {
    if(_routeThroughPunchthroughAddress) {
        [_connectionGovernor sendUdpPacket:packet toPreparedAddress:_punchthroughAddress toPreparedPort:_punchthroughPort];
    } else {
        if([self isNatPunchthroughAddressLoaded] && [_natPunchthroughDiscoveryTimer getState]) {
            NSLog(@"Sending discovery packet");
            [_connectionGovernor sendUdpPacket:_natPunchthroughDiscoveryPacket toPreparedAddress:_punchthroughAddress toPreparedPort:_punchthroughPort];
        }
        
        [_connectionGovernor sendUdpPacket:packet];
    }
}

- (id<NewPacketDelegate>) getTcpOutputSession {
    return [[ConnectionGovernorProtocolTcpSession alloc] initWithConnectionManager:self];
}
- (id<NewPacketDelegate>) getUdpOutputSession {
    return [[ConnectionGovernorProtocolUdpSession alloc] initWithConnectionManager:self];
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    if(protocol == UDP) {
        [_recvDelegate onNewPacket:packet fromProtocol:protocol];
    } else if(protocol == TCP) {
        unsigned int prefix = [packet getUnsignedInteger];
        if(prefix == NAT_PUNCHTHROUGH_ADDRESS) {
            _punchthroughAddress = [packet getUnsignedInteger];
            _punchthroughPort = [packet getUnsignedInteger];
            NSLog(@"Loaded punch through address: %d / %d", _punchthroughAddress, _punchthroughPort);
        } else {
            // Not a packet that we care about, pass it downstream.
            [packet setCursorPosition:0];
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        NSLog(@"Invalid protocol");
    }
}

- (Boolean)isNatPunchthroughAddressLoaded {
    return _punchthroughAddress != 0 && _punchthroughPort != 0;
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol fromAddress:(uint)address andPort:(ushort)port {
    if([self isNatPunchthroughAddressLoaded] && address == _punchthroughAddress && port == _punchthroughPort) {
        _routeThroughPunchthroughAddress = true;
        unsigned int prefix = [packet getUnsignedIntegerAtPosition:0];
        if(prefix == NAT_PUNCHTHROUGH_DISCOVERY) {
            NSLog(@"Discovery packet received");
        } else {
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        NSLog(@"Dropping unknown packet from address: %d / %d", address, port);
    }
}
@end
