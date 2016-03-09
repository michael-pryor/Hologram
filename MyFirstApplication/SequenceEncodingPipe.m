//
// Created by Michael Pryor on 09/03/2016.
//

#import "SequenceEncodingPipe.h"


@implementation SequenceEncodingPipe {
    uint16_t _currentId;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession {
    self = [super init];
    if (self) {
        _currentId = 0;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint16_t idToUse;
    @synchronized (self) {
        // overflow is okay.
        idToUse = _currentId;
        _currentId++;
    }
    [packet addUnsignedInteger16:idToUse];
    [_outputSession onNewPacket:packet fromProtocol:protocol];
}
@end