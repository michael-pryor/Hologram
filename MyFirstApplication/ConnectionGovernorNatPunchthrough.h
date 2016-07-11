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
#import "MatchingViewController.h"

typedef enum {
    NONE, // Initial state when we've just started up.
    PUNCHED_THROUGH, // Punched through, so packets are going direct to end point.
    ROUTED, // Not punched through; we are going via the central server (costing me money).
    ADDRESS_RECEIVED // Received the address of a client, to attempt NAT punchthrough discovery with.
    // Every time we interact with a new client, this will happen.
    // Useful to know when e.g. a skip request has completed.
} NatState;

@protocol NatPunchthroughNotifier;

@interface ConnectionGovernorNatPunchthrough : NSObject <ConnectionGovernor, NewPacketDelegate, NewUnknownPacketDelegate, ConnectionStatusDelegateProtocol>
- (id)initWithRecvDelegate:(id <NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id <ConnectionStatusDelegateProtocol>)connectionStatusDelegate loginProvider:(id <LoginProvider>)loginProvider punchthroughNotifier:(id <NatPunchthroughNotifier>)notifier;

- (void)connectToTcpHost:(NSString *)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString *)udpHost udpPort:(ushort)udpPort;

- (void)sendTcpPacket:(ByteBuffer *)packet;

- (void)sendUdpPacket:(ByteBuffer *)packet;

- (id <NewPacketDelegate>)getTcpOutputSession;

- (id <NewPacketDelegate>)getUdpOutputSession;

- (Boolean)isConnected;

- (void)shutdown;

- (void)terminate;

- (Boolean)isTerminated;

- (void)disableReconnecting;
@end

@protocol NatPunchthroughNotifier <CallingCardDataProvider>
- (void)onNatPunchthrough:(ConnectionGovernorNatPunchthrough *)connection stateChange:(NatState)state;

- (void)handleKarmaMaximum:(uint)karmaMaximum ratingTimeoutSeconds:(uint)ratingTimeoutSeconds matchDecisionTimeout:(uint)timeout;

- (void)handleOurKarma:(uint)ourKarma remoteKarma:(uint)remoteKarma;
@end
