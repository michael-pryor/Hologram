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
    uint _leftPadding;
    ByteBuffer* _sendBuffer;
}
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession andChunkSize:(uint)chunkSize withLeftPadding:(uint)leftPadding {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _leftPadding = leftPadding;
        _chunkSize = chunkSize;
        _batchId = 0;
        _sendBuffer = [[ByteBuffer alloc] initWithSize:chunkSize + (sizeof(uint) * 2) + _leftPadding]; // space for IDs and padding too.
        [_sendBuffer setUsedSize:_sendBuffer.bufferMemorySize];
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = 0;
    while([packet getUnreadDataFromCursor] > 0) {
        ByteBuffer* chunk = [self getChunkToSendFromBatch:packet withBatchId:_batchId withChunkId:chunkId];
        chunkId++;

        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}
- (ByteBuffer*)getChunkToSendFromBatch:(ByteBuffer*)batchPacket withBatchId:(uint)batchId withChunkId:(uint)chunkId {
    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = _leftPadding;
    
    [_sendBuffer addUnsignedInteger:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
 
    // TODO: inefficiencies here copying buffers around and allocating memory.
    memcpy(_sendBuffer.buffer + _sendBuffer.cursorPosition, batchPacket.buffer + batchPacket.cursorPosition, _chunkSize);
    batchPacket.cursorPosition += _chunkSize;
    _sendBuffer.cursorPosition += _chunkSize;
    
    return _sendBuffer;
}
@end
