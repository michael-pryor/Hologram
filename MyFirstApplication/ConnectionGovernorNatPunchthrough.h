//
//  ConnectionManagerProtocolWithNatPunchtrough.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/06/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionGovernorProtocol.h"
#import "InputSessionBase.h"

@interface ConnectionGovernorNatPunchthrough : ConnectionGovernorProtocol<NewPacketDelegate, NewUnknownPacketDelegate>
- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate;
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void)sendTcpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet;
- (id<NewPacketDelegate>)getTcpOutputSession;
- (id<NewPacketDelegate>)getUdpOutputSession;
- (Boolean)isConnected;
- (void)shutdown;
@end
