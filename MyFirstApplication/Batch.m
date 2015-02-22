//
//  BatcherInputBatch.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import "Batch.h"
#import "ByteBuffer.h"

@implementation Batch {
    uint _chunksReceived;
    uint _chunkSize;
    uint _numChunksThreshold;
    ByteBuffer* _partialPacket;
}

- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(uint)numChunksThreshold {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunksReceived = 0;
        _numChunksThreshold = numChunksThreshold;
        _chunkSize = chunkSize;
        _partialPacket = [[ByteBuffer alloc] initWithSize:numChunks * chunkSize];
    }
    return self;
}

- (uint)getBufferPositionFromChunkId: (uint)chunkId {
    return chunkId * _chunkSize;
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = [packet getUnsignedInteger];
    uint buffPosition = [self getBufferPositionFromChunkId: chunkId];
    
    // Copy contents of chunk packet into partial packet.
    [_partialPacket addByteBuffer:packet includingPrefix:false atPosition:buffPosition startingFrom:[packet cursorPosition]];
    
    _chunksReceived += 1;
}

@end
