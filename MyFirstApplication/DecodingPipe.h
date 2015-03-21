//
//  DecodingPipe.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 21/03/2015.
//
//

#import "PipelineProcessor.h"
#import "InputSessionBase.h"

@interface DecodingPipe : NSObject<NewPacketDelegate>
- (id)init;
- (void)addPrefix:(uint)prefix mappingToOutputSession:(id<NewPacketDelegate>)outputSession;
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end
