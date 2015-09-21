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

typedef enum {
    PUNCHED_THROUGH, // Punched through, so packets are going direct to end point.
    ROUTED // Not punched through; we are going via the central server (costing me money).
} NatState;

@protocol NatPunchthroughNotifier;

@interface ConnectionGovernorNatPunchthrough : NSObject<ConnectionGovernor, NewPacketDelegate, NewUnknownPacketDelegate>
- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate loginProvider:(id<LoginProvider>)loginProvider punchthroughNotifier:(id<NatPunchthroughNotifier>)notifier;
- (void)connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort;
- (void)sendTcpPacket:(ByteBuffer*)packet;
- (void)sendUdpPacket:(ByteBuffer*)packet;
- (id<NewPacketDelegate>)getTcpOutputSession;
- (id<NewPacketDelegate>)getUdpOutputSession;
- (Boolean)isConnected;
- (void)shutdown;
@end

@protocol NatPunchthroughNotifier
- (void)onNatPunchthrough:(ConnectionGovernorNatPunchthrough*)connection stateChange:(NatState)state;
@end
