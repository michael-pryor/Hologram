//
//  BatcherOutput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherOutput.h"

uint sleep_threshold = 8;
double sleep_amount = 0.01;
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

        // Formula for estimated latency impact in milliseconds:
        // (bytes_per_chunk / sleep_threshold) * (sleep_amount * 1000)
        //
        // So this is:
        // (96 / 8) * (0.01 * 1000) = 120ms
        //
        // This logic is necessary because iOS send queues are limited in size; exceeding this
        // causes packets to be dropped without any indication as to which were dropped (no attempt
        // is made to send this). This logic tries to hold back and not exceed this limit, giving
        // time for packets to be sent.
        if(chunkId % sleep_threshold == 0) {
            [NSThread sleepForTimeInterval:sleep_amount];
        }

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
