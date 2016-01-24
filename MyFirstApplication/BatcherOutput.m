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
        uint maximumChunkSize = 256;
        _sendBuffer = [[ByteBuffer alloc] initWithSize:maximumChunkSize + (sizeof(uint) * 3) + sizeof(uint8_t) + _leftPadding]; // space for IDs and padding too.
        _batchSizeGenerator = [[BatchSizeGenerator alloc] initWithDesiredBatchSize:128 minimum:90 maximum:maximumChunkSize maximumPacketSize:15000];
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

    // By contract chunkSize and remainder cannot be more than 256 bytes.
    uint8_t lastChunkSize;
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

- (ByteBuffer *)getChunkToSendFromBatch:(ByteBuffer *)batchPacket batchId:(uint)batchId chunkId:(uint)chunkId numChunks:(uint)numChunks chunkSizeBytes:(uint)chunkSizeBytes lastChunkSize:(uint8_t)lastChunkSize {
    if (chunkId >= numChunks) {
        NSLog(@"Chunk ID >= num chunks %d vs %d", chunkId, numChunks);
    }

    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = _leftPadding;

    [_sendBuffer addUnsignedInteger:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
    [_sendBuffer addUnsignedInteger:numChunks]; // total number of chunks in this batch.
    [_sendBuffer addUnsignedInteger8:lastChunkSize]; // size of last chunk in batch.

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

    //NSLog(@"Splitter - generated chunk with batch ID: %d, chunkID: %d, num chunks: %d, last chunk size: %d, full batch size real: %d  full batch size calculated: %d, current chunk packet size: %d, current buff position: %d, unread data in batch: %d", batchId, chunkId, numChunks, lastChunkSize, [batchPacket bufferUsedSize], ((numChunks - 1) * chunkSizeBytes) + lastChunkSize, [_sendBuffer bufferUsedSize], [batchPacket cursorPosition] - auxChunkSize, unreadData);

    return _sendBuffer;
}
@end
