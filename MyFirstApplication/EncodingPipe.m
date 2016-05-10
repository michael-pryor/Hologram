#import "EncodingPipe.h"

@implementation EncodingPipe {
    uint8_t _prefix;
    uint _position;
    bool _insertAtCursor;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint8_t)prefix {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _prefix = prefix;
        _position = 0; // ignored.
        _insertAtCursor = true;
    }
    return self;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession prefixId:(uint8_t)prefix position:(uint)position {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _prefix = prefix;
        _position = position;
        _insertAtCursor = false;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (!_insertAtCursor) {
        [packet addUnsignedInteger8:_prefix atPosition:_position];
    } else {
        // Will move cursor.
        [packet addUnsignedInteger8:_prefix];
    }
    [_outputSession onNewPacket:packet fromProtocol:protocol];
}
@end