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

@protocol ConnectionStatusDelegateProtocol
- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription: (NSString*)description;
@end

@interface ConnectionGovernorProtocol : NSObject<ConnectionGovernor>
- (id) initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate unknownRecvDelegate:(id<NewUnknownPacketDelegate>)unknownRecvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate;
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void)sendTcpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet toPreparedAddress:(uint)address toPreparedPort:(ushort)port;
- (void)sendUdpPacket:(ByteBuffer*)packet toAddress:(NSString*)address toPort:(ushort)port;
- (id<NewPacketDelegate>)getTcpOutputSession;
- (id<NewPacketDelegate>)getUdpOutputSession;
- (Boolean)isConnected;
- (void)shutdown;
@end