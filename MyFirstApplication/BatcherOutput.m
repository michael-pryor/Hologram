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
    ByteBuffer *_sendBuffer;
    Boolean _includeTotalChunks;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession andChunkSize:(uint)chunkSize withLeftPadding:(uint)leftPadding includeTotalChunks:(Boolean)includeTotalChunks {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _leftPadding = leftPadding;
        _chunkSize = chunkSize;
        _batchId = 0;

        uint numIntegers = 2;
        if (includeTotalChunks) {
            numIntegers++;
        }

        _sendBuffer = [[ByteBuffer alloc] initWithSize:chunkSize + (sizeof(uint) * numIntegers) + _leftPadding]; // space for IDs and padding too.
        [_sendBuffer setUsedSize:_sendBuffer.bufferMemorySize];
        _includeTotalChunks = includeTotalChunks;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = 0;

    // Calculate total number of chunks in this batch.
    uint estimatedChunks;
    if (_includeTotalChunks) {
        uint bufferSize = [packet getUnreadDataFromCursor];
        uint extraChunks;
        if (bufferSize % _chunkSize > 0) {
            extraChunks = 1;
        } else {
            extraChunks = 0;
        }
        estimatedChunks = (bufferSize / _chunkSize) + extraChunks;
    } else {
        estimatedChunks = 0; // we don't care, since we don't need to send this value.
    }

    // Send chunks.
    while ([packet getUnreadDataFromCursor] > 0) {
        ByteBuffer *chunk = [self getChunkToSendFromBatch:packet withBatchId:_batchId withChunkId:chunkId andEstimatedChunks:estimatedChunks];
        chunkId++;

        [_outputSession onNewPacket:chunk fromProtocol:protocol];
    }
    _batchId++;
}

- (ByteBuffer *)getChunkToSendFromBatch:(ByteBuffer *)batchPacket withBatchId:(uint)batchId withChunkId:(uint)chunkId andEstimatedChunks:(uint)estimatedChunks {
    // Enough space to do something meaningful.
    _sendBuffer.cursorPosition = _leftPadding;

    [_sendBuffer addUnsignedInteger:batchId]; // batch ID.
    [_sendBuffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
    [_sendBuffer setCursorPosition:_sendBuffer.cursorPosition - 4];
    uint test = [_sendBuffer getUnsignedInteger];
    if (_includeTotalChunks) {
        [_sendBuffer addUnsignedInteger:estimatedChunks]; // total number of chunks in this batch.
    }

    // Last chunk may be smaller.
    uint auxChunkSize;
    uint unreadData = [_sendBuffer getUnreadDataFromCursor];
    if (_chunkSize > unreadData) {
        auxChunkSize = unreadData;
    } else {
        auxChunkSize = _chunkSize;
    }

    // TODO: inefficiencies here copying buffers around and allocating memory.
    memcpy(_sendBuffer.buffer + _sendBuffer.cursorPosition, batchPacket.buffer + batchPacket.cursorPosition, auxChunkSize);
    batchPacket.cursorPosition += auxChunkSize;
    _sendBuffer.cursorPosition += auxChunkSize;

    return _sendBuffer;
}
@end
