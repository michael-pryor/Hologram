//
//  BatcherOutput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherOutput.h"

@implementation BatcherOutput {
    uint _chunkSize;
    uint _batchId;
}
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession andChunkSize:(uint)chunkSize {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunkSize = chunkSize;
        _batchId = 0;
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = 0;
    while([packet getUnreadDataFromCursor] > 0) {
        ByteBuffer* chunk = [self getChunkToSendFromBatch:packet withBatchId:_batchId withChunkId:chunkId];
        chunkId++;
        [NSThread sleepForTimeInterval:0.01]; // <------ we are sending too quickly, OS is dropping UDP packets without even trying to send them :(
        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}
- (ByteBuffer*)getChunkToSendFromBatch:(ByteBuffer*)batchPacket withBatchId:(uint)batchId withChunkId:(uint)chunkId {
    // Enough space to do something meaningful.
    ByteBuffer* buffer = [[ByteBuffer alloc] initWithSize:(_chunkSize + sizeof(uint) * 2)];
    
    [buffer addUnsignedInteger:batchId]; // batch ID.
    [buffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
 
    // TODO: inefficiencies here copying buffers around and allocating memory.
    [buffer addByteBuffer: [batchPacket getByteBufferWithLength:_chunkSize] includingPrefix:false];
    
    return buffer;
}
@end
