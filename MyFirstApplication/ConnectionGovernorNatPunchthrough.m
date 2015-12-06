//
//  ConnectionManagerProtocolWithNatPunchtrough.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/06/2015.
//
//

#import "ConnectionGovernorNatPunchthrough.h"
#import "NetworkOperations.h"
#import "Timer.h"
#import "NetworkUtility.h"

@implementation ConnectionGovernorNatPunchthrough {
    ConnectionGovernorProtocol *_connectionGovernor;
    id <NewPacketDelegate> _recvDelegate;
    uint _punchthroughAddress;
    uint _punchthroughPort;
    Boolean _routeThroughPunchthroughAddress;
    Timer *_natPunchthroughDiscoveryTimer;
    ByteBuffer *_natPunchthroughDiscoveryPacket;
    id <NatPunchthroughNotifier> _notifier;
    id <ConnectionStatusDelegateProtocol> _connectionStatusDelegate;
}
- (id)initWithRecvDelegate:(id <NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id <ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id <SlowNetworkDelegate>)slowNetworkDelegate loginProvider:(id <LoginProvider>)loginProvider punchthroughNotifier:(id <NatPunchthroughNotifier>)notifier {
    if (self) {
        _notifier = notifier;
        _connectionStatusDelegate = connectionStatusDelegate;

        _recvDelegate = recvDelegate;
        _connectionGovernor = [[ConnectionGovernorProtocol alloc] initWithRecvDelegate:self unknownRecvDelegate:self connectionStatusDelegate:self slowNetworkDelegate:slowNetworkDelegate loginProvider:loginProvider];

        [self clearNatPunchthrough];
        _natPunchthroughDiscoveryTimer = [[Timer alloc] initWithFrequencySeconds:0.5 firingInitially:true];

        _natPunchthroughDiscoveryPacket = [[ByteBuffer alloc] initWithSize:sizeof(uint)];
        [_natPunchthroughDiscoveryPacket addUnsignedInteger:NAT_PUNCHTHROUGH_DISCOVERY];
    }
    return self;
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    if (status == P_NOT_CONNECTED || status == P_NOT_CONNECTED_HASH_REJECTED) {
        NSLog(@"Disconnected; clearing NAT punchthrough");
        [self clearNatPunchthrough];
    }
    [_connectionStatusDelegate connectionStatusChange:status withDescription:description];
}

- (void)connectionStatusChangeTcp:(ConnectionStatusTcp)status withDescription:(NSString *)description {
    [_connectionGovernor connectionStatusChangeTcp:status withDescription:description];
}

- (void)connectionStatusChangeUdp:(ConnectionStatusUdp)status withDescription:(NSString *)description {
    [_connectionGovernor connectionStatusChangeUdp:status withDescription:description];
}

- (void)disableReconnecting {
    [_connectionGovernor disableReconnecting];
}

- (void)shutdown {
    [_connectionGovernor shutdown];
    [self clearNatPunchthrough];
}

- (void)terminate {
    [_connectionGovernor terminate];
    [self clearNatPunchthrough];
}

- (Boolean)isTerminated {
    return [_connectionGovernor isTerminated];
}

- (Boolean)isConnected {
    return [_connectionGovernor isConnected];
}


- (void)connectToTcpHost:(NSString *)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString *)udpHost udpPort:(ushort)udpPort {
    [self clearNatPunchthrough];
    [_connectionGovernor connectToTcpHost:tcpHost tcpPort:tcpPort udpHost:udpHost udpPort:udpPort];
}

- (void)sendTcpPacket:(ByteBuffer *)packet {
    [_connectionGovernor sendTcpPacket:packet];
}

- (void)sendUdpPacket:(ByteBuffer *)packet {
    if (_routeThroughPunchthroughAddress) {
        [_connectionGovernor sendUdpPacket:packet toPreparedAddress:_punchthroughAddress toPreparedPort:_punchthroughPort];
    } else {
        if ([self isNatPunchthroughAddressLoaded] && [_natPunchthroughDiscoveryTimer getState]) {
            NSLog(@"Sending discovery packet");
            [_connectionGovernor sendUdpPacket:_natPunchthroughDiscoveryPacket toPreparedAddress:_punchthroughAddress toPreparedPort:_punchthroughPort];
        }

        [_connectionGovernor sendUdpPacket:packet];
    }
}

- (id <NewPacketDelegate>)getTcpOutputSession {
    return [[ConnectionGovernorProtocolTcpSession alloc] initWithConnectionManager:self];
}

- (id <NewPacketDelegate>)getUdpOutputSession {
    return [[ConnectionGovernorProtocolUdpSession alloc] initWithConnectionManager:self];
}

- (void)clearNatPunchthrough {
    _routeThroughPunchthroughAddress = false;
    _punchthroughAddress = 0;
    _punchthroughPort = 0;
    [_notifier onNatPunchthrough:self stateChange:ROUTED];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (protocol == UDP) {
        unsigned int prefix = [packet getUnsignedIntegerAtPosition:0];
        if (prefix == NAT_PUNCHTHROUGH_DISCOVERY) {
            // As a precaution.
            NSLog(@"Discovery packet received on master connection, dropping packet");
        } else {
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else if (protocol == TCP) {
        unsigned int prefix = [packet getUnsignedInteger];
        if (prefix == NAT_PUNCHTHROUGH_ADDRESS) {
            _punchthroughAddress = [packet getUnsignedInteger];
            _punchthroughPort = [packet getUnsignedInteger];
            NSString *humanAddress = [NetworkUtility convertPreparedAddress:_punchthroughAddress port:_punchthroughPort];
            NSLog(@"Loaded punch through address: %d / %d - this is: %@", _punchthroughAddress, _punchthroughPort, humanAddress);

            NSString *userName = [packet getString];
            uint userAge = [packet getUnsignedInteger];

            [_notifier onNatPunchthrough:self stateChange:ADDRESS_RECEIVED];
            [_notifier handleUserName:userName age:userAge];
        } else if (prefix == NAT_PUNCHTHROUGH_DISCONNECT) {
            NSLog(@"Request to stop using NAT punchthrough received");
            [self clearNatPunchthrough];
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

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol fromAddress:(uint)address andPort:(ushort)port {
    if ([self isNatPunchthroughAddressLoaded] && address == _punchthroughAddress && port == _punchthroughPort) {
        if (!_routeThroughPunchthroughAddress) {
            [_notifier onNatPunchthrough:self stateChange:PUNCHED_THROUGH];
            _routeThroughPunchthroughAddress = true;
        }
        unsigned int prefix = [packet getUnsignedIntegerAtPosition:0];
        if (prefix == NAT_PUNCHTHROUGH_DISCOVERY) {
            NSString *addressConverted = [NetworkUtility convertPreparedAddress:address port:port];
            NSLog(@"Discovery packet received from: %@", addressConverted);
        } else {
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        NSLog(@"Dropping unknown packet from address: %d / %d", address, port);
    }
}
@end
