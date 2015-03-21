#import "EncodingPipe.h"

@implementation EncodingPipe {
    uint _prefix;
}
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession andPrefixId:(uint)prefix {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _prefix = prefix;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    [packet addUnsignedInteger:_prefix atPosition:0];
    [_outputSession onNewPacket:packet fromProtocol:protocol];
}
@end