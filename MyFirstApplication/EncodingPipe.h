#import "PipelineProcessor.h"
#import "InputSessionBase.h"

@interface EncodingPipe : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint)prefix;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint)prefix position:(uint)position;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint)prefix position:(uint)position doLogging:(bool)doLogging;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)setPrefix:(uint)prefix;
@end