//
// Created by Michael Pryor on 23/01/2016.
//

#import <XCTest/XCTest.h>
#import "BatcherOutput.h"

@interface BatchingTest : XCTestCase <NewPacketDelegate>
@end

@implementation BatchingTest {
    ByteBuffer *_resultingBuffer;
    uint _chunkSizeBytes;
    uint _leftPadding;
}
- (void)setUp {
    [super setUp];
    _resultingBuffer = [[ByteBuffer alloc] initWithSize:128];
    _chunkSizeBytes = 0;
    _leftPadding = 4;
}

- (void)testBatcherOutput {
    BatcherOutput *batcherOutput = [[BatcherOutput alloc] initWithOutputSession:self leftPadding:_leftPadding];

    ByteBuffer *testData = [[ByteBuffer alloc] initWithSize:2048];
    [testData setUsedSize:[testData bufferMemorySize]];
    [testData setCursorPosition:0];

    for (int n = 0; n < [testData bufferUsedSize]; n++) {
        testData.buffer[n] = n;
    }

    [batcherOutput onNewPacket:testData fromProtocol:UDP];

    assert(_resultingBuffer.bufferUsedSize == testData.bufferUsedSize);
    assert(_resultingBuffer.cursorPosition == 0);

    for (int n = 0;n < [_resultingBuffer bufferUsedSize]; n++) {
        assert(_resultingBuffer.buffer[n] == testData.buffer[n]);
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    [packet setCursorPosition:_leftPadding];
    
    uint batchId = [packet getUnsignedInteger];
    uint chunkId = [packet getUnsignedInteger];
    uint totalChunks = [packet getUnsignedInteger];
    uint lastChunkSize = [packet getUnsignedInteger];

    if (chunkId == totalChunks - 1) {
        assert(lastChunkSize == [packet getUnreadDataFromCursor]);
    } else {
        _chunkSizeBytes = [packet getUnreadDataFromCursor];
    }

    [_resultingBuffer addByteBuffer:packet includingPrefix:false atPosition:chunkId * _chunkSizeBytes startingFrom:[packet cursorPosition]];
}


@end