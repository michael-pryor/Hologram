//
//  InputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "InputSession.h"

@implementation InputSessionTCP
id<NewPacketDelegate> packetDelegate;
@synthesize recvBuffer;

- (id)initWithDelegate:(id<NewPacketDelegate>)p_packetDelegate {
    self = [super init];
    if(self) {
	    packetDelegate = p_packetDelegate;
        recvBuffer = [[ByteBuffer alloc] initWithSize:1024];
    }
    return self;
}

- (void)onNewData: (uint)length {
    ByteBuffer * dataStream = [self getDestinationBuffer];
    
    // Extract out read packets.
    while(true) {
        NSString * strVersion = [dataStream convertToString];
        
        uint packetSize = [dataStream getUnsignedIntegerAtPosition: 0];
        if(packetSize > 0 && [dataStream bufferUsedSize] >= packetSize) {
            // cursor will always be 0 at this point if everything is working.
            if([dataStream cursorPosition] != 0) {
                NSLog(@"Cursor is not 0 (check 1), something is wrong: %u", [dataStream cursorPosition]);
            }
            
            // Retrieve complete packet.
            ByteBuffer* packet = [dataStream getByteBuffer];
            
            // Erase packet from buffer.
            [dataStream eraseFromCursor:packet.bufferUsedSize + sizeof(uint)];
            
            if([dataStream cursorPosition] != 0) {
                NSLog(@"Cursor is not 0 (check 2), something is wrong: %u", [dataStream cursorPosition]);
            }
            
            // Now do something with packet.
            [packetDelegate onNewPacket:packet];
        } else {
            break;
        }
    }
}

- (ByteBuffer*)getDestinationBuffer {
    return recvBuffer;
}
@end
