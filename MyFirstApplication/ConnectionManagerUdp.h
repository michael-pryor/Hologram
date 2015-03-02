//
//  ConnectionManagerUdp.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerBase.h"
#import "InputSessionBase.h"
#import "ByteBuffer.h"
#import "InputSessionBase.h"

@interface ConnectionManagerUdp : NSObject<ConnectionManagerBase, NewPacketDelegate>
@property (readonly) uint numSockets;

- (id) initWithNewPacketDelegate:(id<NewPacketDelegate>)newPacketDelegate andNumSockets:(uint)numSockets;
- (void) connectToHost: (NSString*) host andPort: (ushort) port;
- (void) shutdown;
- (Boolean) isConnected;

- (void) sendBufferToAllSockets:(ByteBuffer*)buffer;
- (void) sendBufferToPrimary:(ByteBuffer*)primary andToSecondary:(ByteBuffer*)secondary;
- (void) sendBuffer:(ByteBuffer*)buffer toSocketWithId:(uint)socketId;
- (void) sendBuffer:(ByteBuffer*)buffer;
- (void) onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end
