//
//  InputSessionGeneric.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 20/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

// Receives new data from the network stream.
//
// Provides a buffer to receive the data as is notified
// when new data is populated.
//
// This is relevant to streaming protocols e.g. TCP.
@protocol NewDataDelegate
- (void)onNewData: (uint)length;
- (ByteBuffer*)getDestinationBuffer;
@end

typedef enum {
    UDP,
    TCP
} ProtocolType;

// Receives new packets from the session.
//
// A packet is a complete item in the same form as when it
// it was originally sent (no bytes missing or out of order).
@protocol NewPacketDelegate
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end

// Notifies users that network is slow,
// so they should try to reduce network usage.
@protocol SlowNetworkDelegate
- (void)slowNetworkNotification;
@end