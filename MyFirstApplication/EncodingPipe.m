#import "EncodingPipe.h"

@implementation EncodingPipe {
    uint _prefix;
    uint _position;
    bool _doLogging;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint)prefix {
    self = [self initWithOutputSession:outputSession prefixId:prefix position:0];
    return self;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint)prefix position:(uint)position {
    self = [self initWithOutputSession:outputSession prefixId:prefix position:position doLogging:false];
    return self;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint)prefix position:(uint)position doLogging:(bool)doLogging {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _prefix = prefix;
        _position = position;
        _doLogging = doLogging;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (_doLogging) {
        //NSLog(@"Writing prefix of %d", _prefix);
    }

    [packet addUnsignedInteger:_prefix atPosition:_position];
    [_outputSession onNewPacket:packet fromProtocol:protocol];
}

- (void)setPrefix:(uint)prefix {
    _prefix = prefix;
}
@end