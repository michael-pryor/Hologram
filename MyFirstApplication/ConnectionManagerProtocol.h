//
//  ConnectionManagerProtocol.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerTcp.h"
#import "ConnectionManagerBase.h"
#import "InputSessionBase.h"

typedef enum {
    P_CONNECTED,
    P_CONNECTING,
    P_WAITING_FOR_TCP_LOGON_ACK, // internal not reported to user.
    P_WAITING_FOR_UDP_HASH_ACK, // internal not reported to user.
    P_NOT_CONNECTED
} ConnectionStatusProtocol;

@protocol ConnectionStatusDelegateProtocol
- (void)connectionStatusChange: (ConnectionStatusProtocol)status withDescription: (NSString*)description;
@end

@interface ConnectionManagerProtocol : NSObject<ConnectionManagerBase, NewPacketDelegate, ConnectionStatusDelegateTcp>
- (id) initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate andConnectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate;
- (void) connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void) shutdownWithDescription:(NSString*)description;
- (void) sendTcpPacket:(ByteBuffer*)packet;
- (void) sendUdpPacket:(ByteBuffer*)packet;
- (id<OutputSessionBase>) getTcpOutputSession;
- (id<OutputSessionBase>) getUdpOutputSession;
@end

@interface ConnectionManagerProtocolTcpSession : NSObject<OutputSessionBase>
- (id)initWithConnectionManager: (ConnectionManagerProtocol*)connectionManager;
@end

@interface ConnectionManagerProtocolUdpSession : NSObject<OutputSessionBase>
- (id)initWithConnectionManager: (ConnectionManagerProtocol*)connectionManager;
@end