//
//  BatcherOutput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherOutput.h"
#import "BatchSizeGenerator.h"

@implementation BatcherOutput {
    uint _batchId;
    uint _leftPadding;
    ByteBuffer *_sendBuffer;

    BatchSizeGenerator *_batchSizeGenerator;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _leftPadding = leftPadding;
        _batchId = 0;

        // Batch ID, Chunk ID, Total number of chunks in batch, size in bytes of last chunk.
        uint numIntegers = 4;

        uint maximumChunkSize = 256;
        _sendBuffer = [[ByteBuffer alloc] initWithSize:maximumChunkSize + (sizeof(uint) * numIntegers) + _leftPadding]; // space for IDs and padding too.
        _batchSizeGenerator = [[BatchSizeGenerator alloc] initWithDesiredBatchSize:128 minimum:90 maximum:maximumChunkSize maximumPacketSize:2049];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = 0;

    uint bufferSize = [packet getUnreadDataFromCursor];

    uint chunkSize = [_batchSizeGenerator getBatchSize:bufferSize];

    // Calculate total number of chunks in this batch.
    uint extraChunks;

    // Division cuts off the remainder, so need to add one if there is a remainder.
    uint remainder = [_batchSizeGenerator getLastBatchSize:bufferSize];
    if (remainder > 0) {
        extraChunks = 1;
    } else {
        extraChunks = 0;
    }
    uint numChunks = (bufferSize / chunkSize) + extraChunks;

    uint lastChunkSize;
    if (remainder == 0) {
        lastChunkSize = chunkSize;
    } else {
        lastChunkSize = remainder;
    }

    // Send chunks.
    while ([packet getUnreadDataFromCursor] > 0) {
        ByteBuffer *chunk = [self getChunkToSendFromBatch:packet batchId:_batchId chunkId:chunkId numChunks:numChunks chunkSizeBytes:chunkSize lastChunkSize:lastChunkSize];
        chunkId++;

        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}

- (ByteBuffer *)getChunkToSendFromBatch:(ByteBuffer *)batchPacket batchId:(uint)batchId chunkId:(uint)chunkId numChunks:(uint)numChunks chunkSizeBytes:(uint)chunkSizeBytes lastChunkSize:(uint)lastChunkSize {
    if (chunkId >= numChunks) {
        NSLog(@"Chunk ID >= num chunks %d vs %d", chunkId, numChunks);
    }

    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = _leftPadding;

    [_sendBuffer addUnsignedInteger:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
    [_sendBuffer addUnsignedInteger:numChunks]; // total number of chunks in this batch.
    [_sendBuffer addUnsignedInteger:lastChunkSize]; // size of last chunk in batch.

    // Last chunk may be smaller.
    uint auxChunkSize;
    uint unreadData = [batchPacket getUnreadDataFromCursor];
    if (chunkSizeBytes > unreadData) {
        auxChunkSize = unreadData;
    } else {
        auxChunkSize = chunkSizeBytes;
    }

    // TODO: inefficiencies here copying buffers around and allocating memory.
    memcpy(_sendBuffer.buffer + _sendBuffer.cursorPosition, batchPacket.buffer + batchPacket.cursorPosition, auxChunkSize);
    batchPacket.cursorPosition += auxChunkSize;
    _sendBuffer.cursorPosition += auxChunkSize;

    [_sendBuffer setUsedSize:_sendBuffer.cursorPosition];
    [_sendBuffer setCursorPosition:0];
    return _sendBuffer;
}
@end
