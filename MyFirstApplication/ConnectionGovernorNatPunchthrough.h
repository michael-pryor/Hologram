//
//  ConnectionManagerProtocolWithNatPunchtrough.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/06/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionGovernorProtocol.h"

@interface ConnectionGovernorNatPunchthrough : ConnectionGovernorProtocol
- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate;
- (void)sendUdpPacket:(ByteBuffer*)packet;
@end
