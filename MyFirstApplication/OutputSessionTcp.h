//
//  OutputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "ByteBuffer.h"
#import "OutputSessionBase.h"

@interface OutputSessionTcp : NSObject<OutputSessionBase>
- (id) init;
- (void) sendPacket: (ByteBuffer*) packet;
- (ByteBuffer*) processPacket;
@end
