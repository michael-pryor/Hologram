//
//  OutputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "ByteBuffer.h"
#import "InputSessionBase.h"

@interface OutputSessionTcp : NSObject<NewPacketDelegate>
- (id) init;
- (void) onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;
- (ByteBuffer*) processPacket;
@end
