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

typedef enum {
    U_ERROR,
    U_CONNECTED
} ConnectionStatusUdp;

@protocol ConnectionStatusDelegateUdp
- (void)connectionStatusChangeUdp:(ConnectionStatusUdp)status withDescription:(NSString *)description;
@end

// Receives new packet from an unknown sender (not the entity we originally connected to).
//
// A packet is a complete item in the same form as when it
// it was originally sent (no bytes missing or out of order).
@protocol NewUnknownPacketDelegate
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol fromAddress:(uint)address andPort:(ushort)port;
@end

@interface ConnectionManagerUdp : NSObject <ConnectionManagerBase, NewPacketDelegate>
- (id)initWithNewPacketDelegate:(id <NewPacketDelegate>)newPacketDelegate newUnknownPacketDelegate:(id <NewUnknownPacketDelegate>)newUnknownPacketDelegate connectionDelegate:(id <ConnectionStatusDelegateUdp>)connectionDelegate retryCount:(uint)retryCountMax;

- (void)connectToHost:(NSString *)host andPort:(ushort)port;

- (void)shutdown;

- (Boolean)isConnected;

- (void)sendBuffer:(ByteBuffer *)buffer;

- (void)sendBuffer:(ByteBuffer *)buffer toPreparedAddress:(uint)address toPreparedPort:(ushort)port;

- (void)sendBuffer:(ByteBuffer *)buffer toAddress:(NSString *)address toPort:(ushort)port;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;


@end
