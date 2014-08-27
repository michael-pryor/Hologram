//
//  InputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

// Receives new packets from the session.
//
// A packet is a complete item in the same form as when it
// it was originally sent (no bytes missing or out of order).
@protocol NewPacketDelegate
- (void)onNewPacket: (ByteBuffer*)packet;
@end

// Receives new data from the network stream.
//
// Provides a buffer to receive the data as is notified
// when new data is populated.
@protocol NewDataDelegate
- (void)onNewData: (uint)length;
- (ByteBuffer*)getDestinationBuffer;
@end

@interface InputSessionTCP : NSObject<NewDataDelegate>
@property (readonly) ByteBuffer* recvBuffer;
@end


