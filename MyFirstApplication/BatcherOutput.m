//
//  BatcherOutput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherOutput.h"

uint sleep_threshold = 8;
double sleep_amount = 0.02;
@implementation BatcherOutput {
    uint _chunkSize;
    uint _batchId;
    ByteBuffer* _sendBuffer;
}
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession andChunkSize:(uint)chunkSize {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunkSize = chunkSize;
        _batchId = 0;
        _sendBuffer = [[ByteBuffer alloc] initWithSize:chunkSize + sizeof(uint) * 2]; // space for IDs too.
        [_sendBuffer setUsedSize:_sendBuffer.bufferMemorySize];
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
        // (96 / 8) * (0.02 * 1000) = 240ms
        //
        // This logic can be useful if we want to throttle speeds.
        // But we should try to optimize out code as required ;)
        if(chunkId % sleep_threshold == 0) {
            //[NSThread sleepForTimeInterval:sleep_amount];
        }

        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}
- (ByteBuffer*)getChunkToSendFromBatch:(ByteBuffer*)batchPacket withBatchId:(uint)batchId withChunkId:(uint)chunkId {
    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = 0;
    
    [_sendBuffer addUnsignedInteger:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
 
    // TODO: inefficiencies here copying buffers around and allocating memory.
    memcpy(_sendBuffer.buffer + _sendBuffer.cursorPosition, batchPacket.buffer + batchPacket.cursorPosition, _chunkSize);
    batchPacket.cursorPosition += _chunkSize;
    _sendBuffer.cursorPosition += _chunkSize;
    
    return _sendBuffer;
}
@end
