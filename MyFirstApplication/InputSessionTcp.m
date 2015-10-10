//
//  InputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "InputSessionTcp.h"

@implementation InputSessionTcp
@synthesize getDestinationBuffer = _recvBuffer;

- (id)initWithDelegate:(id <NewPacketDelegate>)packetDelegate {
    self = [super init];
    if (self) {
        _packetDelegate = packetDelegate;
        _recvBuffer = [[ByteBuffer alloc] initWithSize:1024];
    }
    return self;
}

- (void)restartSession {
    [_recvBuffer clear];
}

- (void)onNewData:(uint)length {
    ByteBuffer *dataStream = [self getDestinationBuffer];

    // Extract out read packets.
    while (true) {
        uint packetSize = [dataStream getUnsignedIntegerAtPosition:0];
        //  NSLog(@"Waiting for packet of size: %ul, so far: %ul", packetSize, [dataStream bufferUsedSize]);
        if (packetSize > 0 && [dataStream bufferUsedSize] >= packetSize) {
            // cursor will always be 0 at this point if everything is working.
            if ([dataStream cursorPosition] != 0) {
                NSLog(@"Cursor is not 0 (check 1), something is wrong: %u", [dataStream cursorPosition]);
            }

            // Retrieve complete packet.
            ByteBuffer *packet = [dataStream getByteBuffer];

            // Erase packet from buffer.
            [dataStream setCursorPosition:0];
            [dataStream eraseFromCursor:packet.bufferUsedSize + sizeof(uint)];

            if ([dataStream cursorPosition] != 0) {
                NSLog(@"Cursor is not 0 (check 2), something is wrong: %u", [dataStream cursorPosition]);
            }

            // Now do something with packet.
            [packet setCursorPosition:0];
            [_packetDelegate onNewPacket:packet fromProtocol:TCP];
        } else {
            break;
        }
    }
}
@end
