//
//  ConnectionGovernorLogin.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/07/2015.
//
//

#import "ConnectionCommander.h"
#import "ConnectionManagerTcp.h"
#import "NetworkOperations.h"
#import "ConnectionGovernorNatPunchthrough.h"
#import "NetworkUtility.h"

@implementation ConnectionCommander {
    id<NewPacketDelegate> _recvDelegate;
    id<ConnectionStatusDelegateProtocol> _connectionStatusDelegate;
    id<SlowNetworkDelegate> _slowNetworkDelegate;
    id<GovernorSetupProtocol> _governorSetupDelegate;
    ConnectionManagerTcp* _commander;
    OutputSessionTcp* _commanderOutput;
    
    id<ConnectionGovernor> _governor;
    id<LoginProvider> _loginProvider;
}

- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate governorSetupDelegate:(id<GovernorSetupProtocol>)governorSetupDelegate loginProvider:(id<LoginProvider>)loginProvider {
    if (self) {
        _recvDelegate = recvDelegate;
        _connectionStatusDelegate = connectionStatusDelegate;
        _slowNetworkDelegate = slowNetworkDelegate;
        _governorSetupDelegate = governorSetupDelegate;
        
        _commanderOutput = [[OutputSessionTcp alloc] init];
        
        _commander = [[ConnectionManagerTcp alloc] initWithConnectionStatusDelegate:self inputSession:[[InputSessionTcp alloc] initWithDelegate:self] outputSession:_commanderOutput];
        
        _governor = nil;
        _loginProvider = loginProvider;
    }
    return self;
}

// Commander connect.
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort {
    [self shutdown];
    [_commander connectToHost:tcpHost andPort:tcpPort];
}

// Commander packets.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint commanderOperation = [packet getUnsignedInteger];
    if(commanderOperation == COMMANDER_SUCCESS) {
        // Cleanup old governor.
        if(_governor != nil) {
            [_governor shutdown];
        }
        
        // Prepare new governor.
        uint governorAddress = [packet getUnsignedInteger];
        NSString* governorAddressConverted = [NetworkUtility convertPreparedHostName:governorAddress];
        uint governorPortTcp = [packet getUnsignedInteger];
        uint governorPortUdp = [packet getUnsignedInteger];
        _governor = [[ConnectionGovernorNatPunchthrough alloc] initWithRecvDelegate:_recvDelegate connectionStatusDelegate:_connectionStatusDelegate slowNetworkDelegate:_slowNetworkDelegate loginProvider:_loginProvider];
        [_governor connectToTcpHost:governorAddressConverted tcpPort:governorPortTcp udpHost:governorAddressConverted udpPort:governorPortUdp];
        
        // Announce governor.
        [_governorSetupDelegate onNewGovernor:_governor];
    } else if(commanderOperation == COMMANDER_FAILURE) {
        NSString* fault = [packet getString];
        NSLog(@"Failed to retrieve governor server: %@", fault);
        [self shutdownWithDescription:fault];
    } else {
        NSLog(@"Unknown operation");
    }
}

- (void)shutdown {
    if(_governor != nil) {
        [_governor shutdown];
    }
}

- (void)shutdownWithDescription:(NSString*)description {
    [self shutdown];
    [_connectionStatusDelegate connectionStatusChange:P_NOT_CONNECTED withDescription:@"Commander failed to retrieve governor"];
}

// Commander status changes.
- (void)connectionStatusChangeTcp:(ConnectionStatusTcp)status withDescription:(NSString*)description {
    if(status == T_ERROR) {
        [self shutdown];
        NSLog(@"Error in commander connection: %@", description);
    } else if(status == T_CONNECTING) {
        [_connectionStatusDelegate connectionStatusChange:P_CONNECTING withDescription:@"Commander is connecting"];
    } else if(status == T_CONNECTED) {
        // Don't announce through protocol because governor still needs to connect.
        NSLog(@"Commander is connected");
    } else {
        NSLog(@"Unknown commander connection status TCP");
    }
}
@end
