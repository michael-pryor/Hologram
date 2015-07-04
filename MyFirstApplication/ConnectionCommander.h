//
//  ConnectionGovernorLogin.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/07/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionGovernorProtocol.h"
#import "InputSessionBase.h"

@protocol GovernorSetupProtocol
- (void)onNewGovernor:(id<ConnectionGovernor>)governor;
@end

@interface ConnectionCommander : NSObject<NewPacketDelegate, ConnectionStatusDelegateTcp>
- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate governorSetupDelegate:(id<GovernorSetupProtocol>)governorSetupDelegate;
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort;
- (void)shutdown;
@end