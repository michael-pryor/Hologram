#import "PipelineProcessor.h"
#import "InputSessionBase.h"

@interface EncodingPipe : PipelineProcessor
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession andPrefixId:(uint)prefix;
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end