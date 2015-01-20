//
//  OutputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "ByteBuffer.h"

@interface OutputSession : NSObject
- (id) init;
- (void) sendPacket: (ByteBuffer*) packet;
- (ByteBuffer*) processPacket;
@end
