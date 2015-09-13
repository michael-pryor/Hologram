//
//  ConnectionManagerGovernor.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 27/06/2015.
//
//
#import "ConnectionManagerBase.h"
#import "InputSessionBase.h"
#import "ByteBuffer.h"
#import "ConnectionManagerTcp.h"
#import "ConnectionManagerUdp.h"

typedef enum {
    P_CONNECTED,
    P_CONNECTING,
    P_WAITING_FOR_TCP_LOGON_ACK, // internal not reported to user.
    P_WAITING_FOR_UDP_HASH_ACK, // internal not reported to user.
    P_NOT_CONNECTED
} ConnectionStatusProtocol;

@protocol ConnectionGovernor<ConnectionManagerBase, NewPacketDelegate, ConnectionStatusDelegateTcp, ConnectionStatusDelegateUdp>
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void)sendTcpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet;
- (id<NewPacketDelegate>)getTcpOutputSession;
- (id<NewPacketDelegate>)getUdpOutputSession;
- (Boolean)isConnected;
- (void)shutdown;
- (void)terminate;
@end

@interface ConnectionGovernorProtocolTcpSession : NSObject<NewPacketDelegate>
- (id)initWithConnectionManager:(id<ConnectionGovernor>)connectionGovernor;
@end

@interface ConnectionGovernorProtocolUdpSession : NSObject<NewPacketDelegate>
- (id)initWithConnectionManager:(id<ConnectionGovernor>)connectionGovernor;
@end