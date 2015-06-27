//
//  ConnectionManagerGovernor.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 27/06/2015.
//
//


@protocol ConnectionGovernor<ConnectionManagerBase, NewPacketDelegate, ConnectionStatusDelegateTcp, ConnectionStatusDelegateUdp>
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void)sendTcpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet;
- (id<NewPacketDelegate>)getTcpOutputSession;
- (id<NewPacketDelegate>)getUdpOutputSession;
@end