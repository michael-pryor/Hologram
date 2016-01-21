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
    Boolean _includeTotalChunks;

    BatchSizeGenerator *_batchSizeGenerator;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize leftPadding:(uint)leftPadding includeTotalChunks:(Boolean)includeTotalChunks {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _leftPadding = leftPadding;
        _batchId = 0;

        uint numIntegers = 2;
        if (includeTotalChunks) {
            numIntegers++;
        }

        uint maximumChunkSize = 256;
        _sendBuffer = [[ByteBuffer alloc] initWithSize:maximumChunkSize + (sizeof(uint) * numIntegers) + _leftPadding]; // space for IDs and padding too.
        [_sendBuffer setUsedSize:_sendBuffer.bufferMemorySize];
        _includeTotalChunks = includeTotalChunks;

        _batchSizeGenerator = [[BatchSizeGenerator alloc] initWithDesiredBatchSize:128 minimum:90 maximum:maximumChunkSize maximumPacketSize:15000];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = 0;

    uint bufferSize = [packet getUnreadDataFromCursor];

    uint chunkSize = [_batchSizeGenerator getBatchSize:bufferSize];

    // Calculate total number of chunks in this batch.
    uint numChunks;
    if (_includeTotalChunks) {
        uint extraChunks;

        // If there is a remainder, there will be an extra packet.
        if (![_batchSizeGenerator isPerfect:bufferSize]) {
            extraChunks = 1;
        } else {
            extraChunks = 0;
        }
        numChunks = (bufferSize / chunkSize) + extraChunks;
    } else {
        numChunks = 0; // we don't care, since we don't need to send this value.
    }

    // Send chunks.
    while ([packet getUnreadDataFromCursor] > 0) {
        ByteBuffer *chunk = [self getChunkToSendFromBatch:packet batchId:_batchId chunkId:chunkId numChunks:numChunks chunkSizeBytes:chunkSize];
        chunkId++;

        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}

- (ByteBuffer *)getChunkToSendFromBatch:(ByteBuffer *)batchPacket batchId:(uint)batchId chunkId:(uint)chunkId numChunks:(uint)numChunks chunkSizeBytes:(uint)chunkSizeBytes {
    if (chunkId >= numChunks) {
        NSLog(@"Chunk ID >= num chunks %d vs %d", chunkId, numChunks);
    }

    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = _leftPadding;

    [_sendBuffer addUnsignedInteger:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.

    if (_includeTotalChunks) {
        [_sendBuffer addUnsignedInteger:numChunks]; // total number of chunks in this batch.
    }

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
    return _sendBuffer;
}
@end
