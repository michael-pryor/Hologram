//
//  ConnectionManagerProtocolWithNatPunchtrough.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/06/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerProtocol.h"

@interface ConnectionManagerProtocolWithNatPunchtrough : ConnectionManagerProtocol
- (id) initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate;
- (void) sendUdpPacket:(ByteBuffer*)packet;
@end
