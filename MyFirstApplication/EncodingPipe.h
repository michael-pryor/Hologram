#import "PipelineProcessor.h"
#import "InputSessionBase.h"

@interface EncodingPipe : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint8_t)prefix;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint8_t)prefix position:(uint)position;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;
@end