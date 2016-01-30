//
//  ConnectionGovernorLogin.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/07/2015.
//
//

#import "ConnectionCommander.h"
#import "NetworkOperations.h"
#import "NetworkUtility.h"

@implementation ConnectionCommander {
    id <NewPacketDelegate> _recvDelegate;
    id <ConnectionStatusDelegateProtocol> _connectionStatusDelegate;
    id <GovernorSetupProtocol> _governorSetupDelegate;
    ConnectionManagerTcp *_commander;
    OutputSessionTcp *_commanderOutput;

    id <LoginProvider> _loginProvider;
    id <NatPunchthroughNotifier> _natPunchthroughNotifier;

    NSString *_tcpHost;
    ushort _tcpPort;
    bool _terminated;
}

- (id)initWithRecvDelegate:(id <NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id <ConnectionStatusDelegateProtocol>)connectionStatusDelegate governorSetupDelegate:(id <GovernorSetupProtocol>)governorSetupDelegate loginProvider:(id <LoginProvider>)loginProvider punchthroughNotifier:(id <NatPunchthroughNotifier>)notifier {
    if (self) {
        _natPunchthroughNotifier = notifier;

        _recvDelegate = recvDelegate;
        _connectionStatusDelegate = connectionStatusDelegate;
        _governorSetupDelegate = governorSetupDelegate;

        _commanderOutput = [[OutputSessionTcp alloc] init];

        _commander = [[ConnectionManagerTcp alloc] initWithConnectionStatusDelegate:self inputSession:[[InputSessionTcp alloc] initWithDelegate:self] outputSession:_commanderOutput];

        _loginProvider = loginProvider;
        _terminated = false;
    }
    return self;
}

// Commander connect.
- (void)connectToTcpHost:(NSString *)tcpHost tcpPort:(ushort)tcpPort {
    [self shutdown];
    _tcpHost = tcpHost;
    _tcpPort = tcpPort;
    [self _reconnect];
}

- (void)_reconnect {
    if (_terminated) {
        NSLog(@"Commander connection is terminated, ignoring reconnect attempt");
        return;
    }
    [_commander connectToHost:_tcpHost andPort:_tcpPort];
}

// Commander packets.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint commanderOperation = [packet getUnsignedInteger8];
    if (commanderOperation == COMMANDER_SUCCESS) {
        // Prepare new governor.
        uint governorAddress = [packet getUnsignedInteger];
        NSString *governorAddressConverted = [NetworkUtility convertPreparedHostName:governorAddress];
        uint governorPortTcp = [packet getUnsignedInteger];
        uint governorPortUdp = [packet getUnsignedInteger];
        id <ConnectionGovernor> governor = [[ConnectionGovernorNatPunchthrough alloc] initWithRecvDelegate:_recvDelegate connectionStatusDelegate:_connectionStatusDelegate loginProvider:_loginProvider punchthroughNotifier:_natPunchthroughNotifier];
        [governor connectToTcpHost:governorAddressConverted tcpPort:governorPortTcp udpHost:governorAddressConverted udpPort:governorPortUdp];

        // Announce governor.
        [_governorSetupDelegate onNewGovernor:governor];
        [self terminate];
    } else if (commanderOperation == COMMANDER_FAILURE) {
        NSString *fault = [packet getString];
        NSLog(@"Failed to retrieve governor server: %@", fault);
        [self shutdownWithDescription:fault];
    } else {
        NSLog(@"Unknown operation");
    }
}

- (void)shutdown {
    [_commander shutdown];

    // Reconnect after 2 seconds delay.
    if (_tcpHost != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self _reconnect];
        });
    }
}

- (void)terminate {
    _terminated = true;
    [_commander shutdown];
}

- (Boolean)isTerminated {
    return _terminated;
}

- (void)shutdownWithDescription:(NSString *)description {
    [self shutdown];
    [_connectionStatusDelegate connectionStatusChange:P_NOT_CONNECTED withDescription:@"Commander failed to retrieve governor"];
}

// Commander status changes.
- (void)connectionStatusChangeTcp:(ConnectionStatusTcp)status withDescription:(NSString *)description {
    if (status == T_ERROR) {
        [self shutdown];

        NSLog(@"Error in commander connection: %@", description);
    } else if (status == T_CONNECTING) {
        [_connectionStatusDelegate connectionStatusChange:P_CONNECTING withDescription:@"Commander is connecting"];
    } else if (status == T_CONNECTED) {
        // Don't announce through protocol because governor still needs to connect.
        NSLog(@"Commander is connected");
    } else {
        NSLog(@"Unknown commander connection status TCP");
    }
}
@end
