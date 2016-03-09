//
// Created by Michael Pryor on 09/03/2016.
//

#import "SequenceDecodingPipe.h"


@implementation SequenceDecodingPipe {
    uint _lastId;
    bool _receivedFirstId;

    id <SequenceGapNotification> _sequenceGapNotification;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession sequenceGapNotification:(id <SequenceGapNotification>)sequenceGapNotification {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _lastId = 0;
        _receivedFirstId = false;
        _sequenceGapNotification = sequenceGapNotification;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint packetSequenceId = [packet getUnsignedInteger16];

    [_outputSession onNewPacket:packet fromProtocol:protocol];

    uint previousId;
    @synchronized (self) {
        if (!_receivedFirstId) {
            _lastId = packetSequenceId;
            _receivedFirstId = true;
            return;
        }

        previousId = _lastId;
        _lastId = packetSequenceId;
    }
    uint diff = packetSequenceId - previousId;

    // Handle overflow gracefully.
    if (diff < 0) {
        packetSequenceId = UINT16_MAX + packetSequenceId;
        diff = packetSequenceId - previousId;
    }


    // No packet loss.
    if (diff == 1) {
        return;
    }

    // Packet loss, so notify.
    [_sequenceGapNotification onSequenceGap:diff fromSender:self];
}
@end