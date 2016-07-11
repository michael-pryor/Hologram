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
#import "Signal.h"
#import "ImageParsing.h"

@implementation ConnectionGovernorNatPunchthrough {
    ConnectionGovernorProtocol *_connectionGovernor;
    id <NewPacketDelegate> _recvDelegate;
    uint _punchthroughAddress;
    uint _punchthroughPort;
    Signal *_routeThroughPunchthroughAddress;
    Timer *_natPunchthroughDiscoveryTimer;

    ByteBuffer *_natPunchthroughDiscoveryPacket;
    id <NatPunchthroughNotifier> _notifier;
    id <ConnectionStatusDelegateProtocol> _connectionStatusDelegate;

    // If we switch from a network capable of punchthrough to not capable, but lingering packets are in our queues,
    // then we do not want to switch over to punchthrough, but would as a result of those packets. So introduce
    // a small wait to prevent this.
    Timer *_natPunchthroughCooldownTimer;

    // If data flow has stopped for some reason, then regress back to routed mode.
    Timer *_natPunchthroughTimeout;

    // While connecting to server and not yet assigned a match, throttle our send rate, so as to
    // reduce bandwidth required for server.
    Timer *_packetSendingThrottle;
}
- (id)initWithRecvDelegate:(id <NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id <ConnectionStatusDelegateProtocol>)connectionStatusDelegate loginProvider:(id <LoginProvider>)loginProvider punchthroughNotifier:(id <NatPunchthroughNotifier>)notifier {
    if (self) {
        _notifier = notifier;
        _connectionStatusDelegate = connectionStatusDelegate;

        _recvDelegate = recvDelegate;
        _connectionGovernor = [[ConnectionGovernorProtocol alloc] initWithRecvDelegate:self unknownRecvDelegate:self connectionStatusDelegate:self loginProvider:loginProvider];

        [self clearNatPunchthrough];
        _natPunchthroughDiscoveryTimer = [[Timer alloc] initWithFrequencySeconds:0.5 firingInitially:true];

        _natPunchthroughDiscoveryPacket = [[ByteBuffer alloc] initWithSize:sizeof(uint8_t)];
        [_natPunchthroughDiscoveryPacket addUnsignedInteger8:NAT_PUNCHTHROUGH_DISCOVERY];

        _routeThroughPunchthroughAddress = [[Signal alloc] initWithFlag:false];

        _natPunchthroughTimeout = [[Timer alloc] initWithFrequencySeconds:10 firingInitially:false];
        _natPunchthroughCooldownTimer = [[Timer alloc] initWithFrequencySeconds:0.5 firingInitially:false];
        _packetSendingThrottle = [[Timer alloc] initWithFrequencySeconds:0.5 firingInitially:true];
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

- (void)onBannedWithMagnitude:(uint8_t)magnitude expiryTimeSeconds:(uint)numSeconds; {
    [_connectionStatusDelegate onBannedWithMagnitude:magnitude expiryTimeSeconds:numSeconds];
}

- (void)onInactivityRejection {
    [_connectionStatusDelegate onInactivityRejection];
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

- (bool)shouldSendUdpToMaster:(uint)punchThroughAddress {
    return punchThroughAddress != 0 || [_packetSendingThrottle getState];
}

- (void)connectToTcpHost:(NSString *)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString *)udpHost udpPort:(ushort)udpPort {
    [self clearNatPunchthrough];
    [_connectionGovernor connectToTcpHost:tcpHost tcpPort:tcpPort udpHost:udpHost udpPort:udpPort];
}

- (void)sendTcpPacket:(ByteBuffer *)packet {
    [_connectionGovernor sendTcpPacket:packet];
}

- (void)sendUdpPacket:(ByteBuffer *)packet {
    uint punchthroughAddress;
    uint punchthroughPort;
    bool routeThroughPunchthroughAddress;

    @synchronized (_routeThroughPunchthroughAddress) {
        punchthroughAddress = _punchthroughAddress;
        punchthroughPort = _punchthroughPort;
        routeThroughPunchthroughAddress = [_routeThroughPunchthroughAddress isSignaled];
    }

    if (routeThroughPunchthroughAddress) {
        [_connectionGovernor sendUdpPacket:packet toPreparedAddress:punchthroughAddress toPreparedPort:punchthroughPort];

        // Revert to routing mode, something has gone wrong.
        if ([_natPunchthroughTimeout getState]) {
            NSLog(@"Reverting to routing mode, no data through NAT punchthrough for %.1f seconds", [_natPunchthroughTimeout getSecondsSinceLastTick]);
            [self clearNatPunchthrough:false];
        }
    } else {
        if ([self isNatPunchthroughAddressLoaded] && [_natPunchthroughDiscoveryTimer getState]) {
            [_connectionGovernor sendUdpPacket:_natPunchthroughDiscoveryPacket toPreparedAddress:punchthroughAddress toPreparedPort:punchthroughPort];
        }

        if ([self shouldSendUdpToMaster:punchthroughAddress]) {
            [_connectionGovernor sendUdpPacket:packet];
        }
    }
}

- (id <NewPacketDelegate>)getTcpOutputSession {
    return [[ConnectionGovernorProtocolTcpSession alloc] initWithConnectionManager:self];
}

- (id <NewPacketDelegate>)getUdpOutputSession {
    return [[ConnectionGovernorProtocolUdpSession alloc] initWithConnectionManager:self];
}

- (void)clearNatPunchthrough {
    [self clearNatPunchthrough:true];
}

- (void)clearNatPunchthrough:(bool)clearAddress {
    @synchronized (_routeThroughPunchthroughAddress) {
        if (clearAddress) {
            if (_punchthroughAddress == 0) {
                return;
            }
            _punchthroughAddress = 0;
            _punchthroughPort = 0;
        }

        // Important to clear addresses before clearing this flag, to avoid
        // picking up late packets comparing against old address and resetting the flag prematurely.
        [_routeThroughPunchthroughAddress clear];
    }

    [_notifier onNatPunchthrough:self stateChange:ROUTED];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (protocol == UDP) {
        unsigned int prefix = [packet getUnsignedIntegerAtPosition8:0];
        if (prefix == NAT_PUNCHTHROUGH_DISCOVERY) {
            NSLog(@"Ignoring NAT_PUNCHTHROUGH_DISCOVERY from master server");
        } else if (prefix == UDP_HASH) {
            // This happens in peer to peer mode, server won't check these packets because its already getting sufficient data.
            NSLog(@"Ignoring UDP_HASH update form master server");
        } else {
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else if (protocol == TCP) {
        unsigned int prefix = [packet getUnsignedInteger8];
        if (prefix == NAT_PUNCHTHROUGH_ADDRESS) {
            // If we are reconnecting, we may already have an old address.
            // We need to switch back to routing temporarily in case this address is now invalid.
            @synchronized (_routeThroughPunchthroughAddress) {
                [self clearNatPunchthrough];

                // Load in the new address.
                _punchthroughAddress = [packet getUnsignedInteger];
                _punchthroughPort = [packet getUnsignedInteger];
                [_natPunchthroughCooldownTimer reset];
                NSString *humanAddress = [NetworkUtility convertPreparedAddress:_punchthroughAddress port:_punchthroughPort];
                NSLog(@"Loaded punch through address: %d / %d - this is: %@", _punchthroughAddress, _punchthroughPort, humanAddress);
            }

            [_notifier onNatPunchthrough:self stateChange:ADDRESS_RECEIVED];
        } else if (prefix == ADVISE_MATCH_INFORMATION) {
            NSString *userName = [packet getString];
            uint userAge = [packet getUnsignedInteger];
            uint distanceFromUser = [packet getUnsignedInteger];
            uint ratingTimeoutSeconds = [packet getUnsignedInteger]; // TODO: could be received in login instead.
            uint karmaMax = [packet getUnsignedInteger]; // TODO: could be received in login instead.
            uint matchDecisionTimeout = [packet getUnsignedInteger]; // TODO: could be received in login instead.
            uint ourKarmaRating = [packet getUnsignedInteger];
            uint remoteKarmaRating = [packet getUnsignedInteger];
            NSString *cardText = [packet getString];
            NSData *profilePictureData = [packet getData];
            uint profilePictureOrientationInteger = [packet getUnsignedInteger];
            UIImageOrientation profilePictureOrientation = [ImageParsing parseIntegerToOrientation:profilePictureOrientationInteger];
            UIImage *profilePicture = [ImageParsing convertDataToImage:profilePictureData orientation:profilePictureOrientation];

            [_notifier setName:userName profilePicture:profilePicture callingCardText:cardText age:userAge distance:(uint) distanceFromUser karma:remoteKarmaRating maxKarma:karmaMax];
            [_notifier handleKarmaMaximum:karmaMax ratingTimeoutSeconds:ratingTimeoutSeconds matchDecisionTimeout:matchDecisionTimeout];
            [_notifier handleOurKarma:ourKarmaRating remoteKarma:remoteKarmaRating];
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
    @synchronized (_routeThroughPunchthroughAddress) {
        return _punchthroughAddress != 0 && _punchthroughPort != 0;
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol fromAddress:(uint)address andPort:(ushort)port {
    bool doProcessing = false;
    bool notifyPunchedThrough = false;
    @synchronized (_routeThroughPunchthroughAddress) {
        if ([self isNatPunchthroughAddressLoaded] && address == _punchthroughAddress && port == _punchthroughPort) {
            if ([_natPunchthroughCooldownTimer getState] && [_routeThroughPunchthroughAddress signalAll]) {
                notifyPunchedThrough = true;
                [_natPunchthroughTimeout reset];
            }
            doProcessing = true;
        } else {
            NSLog(@"Dropping unknown packet from address: %d / %d", address, port);
        }
    }

    if (notifyPunchedThrough) {
        [_notifier onNatPunchthrough:self stateChange:PUNCHED_THROUGH];
    }

    if (doProcessing) {
        unsigned int prefix = [packet getUnsignedIntegerAtPosition8:0];
        if (prefix == NAT_PUNCHTHROUGH_DISCOVERY) {
            NSString *addressConverted = [NetworkUtility convertPreparedAddress:address port:port];
            NSLog(@"Discovery packet received from: %@", addressConverted);
        } else if (prefix == UDP_HASH) {
            NSLog(@"Ignoring UDP hash received direct from client");
        } else {
            [_natPunchthroughTimeout reset];
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    }
}
@end
