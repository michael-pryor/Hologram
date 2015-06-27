//
//  ConnectionManagerProtocol.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerTcp.h"
#import "ConnectionManagerUdp.h"
#import "ConnectionManagerBase.h"
#import "InputSessionBase.h"
#import "ConnectionGovernor.h"

typedef enum {
    P_CONNECTED,
    P_CONNECTING,
    P_WAITING_FOR_TCP_LOGON_ACK, // internal not reported to user.
    P_WAITING_FOR_UDP_HASH_ACK, // internal not reported to user.
    P_NOT_CONNECTED
} ConnectionStatusProtocol;

@protocol ConnectionStatusDelegateProtocol
- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription: (NSString*)description;
@end

@interface ConnectionGovernorProtocol : NSObject<ConnectionGovernor>
- (id) initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate;
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void)sendTcpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet;
- (id<NewPacketDelegate>)getTcpOutputSession;
- (id<NewPacketDelegate>)getUdpOutputSession;
@end

@interface ConnectionGovernorProtocolTcpSession : NSObject<NewPacketDelegate>
- (id)initWithConnectionManager:(ConnectionGovernorProtocol*)connectionManager;
@end

@interface ConnectionGovernorProtocolUdpSession : NSObject<NewPacketDelegate>
- (id)initWithConnectionManager:(ConnectionGovernorProtocol*)connectionManager;
@end