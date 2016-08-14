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
    uint16_t _batchId;
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
        uint maximumChunkSize = 640; // must fit into uint16_t i.e. <= 65535.
        _sendBuffer = [[ByteBuffer alloc] initWithSize:maximumChunkSize + (sizeof(uint16_t) * 3) + sizeof(uint8_t) + _leftPadding]; // space for IDs and padding too.
        _batchSizeGenerator = [[BatchSizeGenerator alloc] initWithDesiredBatchSize:512 minimum:384 maximum:maximumChunkSize maximumPacketSize:15000];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint16_t chunkId = 0;

    uint bufferSize = [packet getUnreadDataFromCursor];

    uint16_t chunkSize = (uint16_t)[_batchSizeGenerator getBatchSize:bufferSize];

    // Calculate total number of chunks in this batch.
    uint extraChunks;

    // Division cuts off the remainder, so need to add one if there is a remainder.
    uint remainder = [_batchSizeGenerator getLastBatchSize:bufferSize];
    if (remainder > 0) {
        extraChunks = 1;
    } else {
        extraChunks = 0;
    }
    uint16_t numChunks = (uint16_t)((bufferSize / chunkSize) + extraChunks);

    // By contract chunkSize and remainder cannot be more than 255 bytes.
    uint8_t lastChunkSize;
    if (remainder == 0) {
        lastChunkSize = (uint8_t)chunkSize;
    } else {
        lastChunkSize = (uint8_t)remainder;
    }

    // Send chunks.
    while ([packet getUnreadDataFromCursor] > 0) {
        ByteBuffer *chunk = [self getChunkToSendFromBatch:packet batchId:_batchId chunkId:chunkId numChunks:numChunks chunkSizeBytes:chunkSize lastChunkSize:lastChunkSize];
        chunkId++;

        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}

- (ByteBuffer *)getChunkToSendFromBatch:(ByteBuffer *)batchPacket batchId:(uint16_t)batchId chunkId:(uint16_t)chunkId numChunks:(uint16_t)numChunks chunkSizeBytes:(uint16_t)chunkSizeBytes lastChunkSize:(uint8_t)lastChunkSize {
    if (chunkId >= numChunks) {
        NSLog(@"Chunk ID >= num chunks %d vs %d", chunkId, numChunks);
    }

    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = _leftPadding;

    [_sendBuffer addUnsignedInteger16:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger16:chunkId]; // chunk ID; ID within batch.
    [_sendBuffer addUnsignedInteger16:numChunks]; // total number of chunks in this batch.
    [_sendBuffer addUnsignedInteger16:lastChunkSize]; // size of last chunk in batch.

    // Last chunk may be smaller.
    uint auxChunkSize;
    uint unreadData = [batchPacket getUnreadDataFromCursor];
    if (chunkSizeBytes > unreadData) {
        auxChunkSize = unreadData;
    } else {
        auxChunkSize = chunkSizeBytes;
    }

    memcpy(_sendBuffer.buffer + _sendBuffer.cursorPosition, batchPacket.buffer + batchPacket.cursorPosition, auxChunkSize);
    batchPacket.cursorPosition += auxChunkSize;
    _sendBuffer.cursorPosition += auxChunkSize;

    [_sendBuffer setUsedSize:_sendBuffer.cursorPosition];
    [_sendBuffer setCursorPosition:0];

    //NSLog(@"Splitter - generated chunk with batch ID: %d, chunkID: %d, num chunks: %d, last chunk size: %d, full batch size real: %d  full batch size calculated: %d, current chunk packet size: %d, current buff position: %d, unread data in batch: %d", batchId, chunkId, numChunks, lastChunkSize, [batchPacket bufferUsedSize], ((numChunks - 1) * chunkSizeBytes) + lastChunkSize, [_sendBuffer bufferUsedSize], [batchPacket cursorPosition] - auxChunkSize, unreadData);

    return _sendBuffer;
}

- (void)dealloc {
    NSLog(@"BatcherOutput dealloc");
}
@end
