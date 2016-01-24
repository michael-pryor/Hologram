//
// Created by Michael Pryor on 23/01/2016.
//

#import <XCTest/XCTest.h>
#import "BatcherOutput.h"
#import "BatcherInput.h"

@interface BatcherInputResultCapture : NSObject <NewPacketDelegate>
@property (readonly) bool fired;
@end

@implementation BatcherInputResultCapture {
    ByteBuffer *_expectedResult;
}
- (id)initWithByteBuffer:(ByteBuffer *)buffer {
    self = [super init];
    if (self) {
        _expectedResult = buffer;
        _fired = false;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    _fired = true;

    assert([packet bufferUsedSize] == [_expectedResult bufferUsedSize]);
    assert([packet cursorPosition] == 0);

    for (int n = 0; n < [_expectedResult bufferUsedSize]; n++) {
        _expectedResult.buffer[n] = packet.buffer[n];
    }
}

@end

@interface BatchingTest : XCTestCase <NewPacketDelegate>
@end

@implementation BatchingTest {
    BatcherInput *_batcherInput;
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

    ByteBuffer *testData = [[ByteBuffer alloc] initWithSize:2046];
    [testData setUsedSize:[testData bufferMemorySize]];
    [testData setCursorPosition:0];

    for (int n = 0; n < [testData bufferUsedSize]; n++) {
        testData.buffer[n] = n;
    }

    BatcherInputResultCapture* batcherInputResultCapture = [[BatcherInputResultCapture alloc] initWithByteBuffer:testData];
    _batcherInput = [[BatcherInput alloc] initWithOutputSession:batcherInputResultCapture numChunksThreshold:1.0f timeoutMs:1000 performanceInformationDelegate:nil];

    [batcherOutput onNewPacket:testData fromProtocol:UDP];

    assert(_resultingBuffer.bufferUsedSize == testData.bufferUsedSize);
    assert(_resultingBuffer.cursorPosition == 0);

    for (int n = 0; n < [_resultingBuffer bufferUsedSize]; n++) {
        assert(_resultingBuffer.buffer[n] == testData.buffer[n]);
    }

    NSDate *loopUntil = [NSDate dateWithTimeIntervalSinceNow:2];
    while (![batcherInputResultCapture fired] && [loopUntil timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:loopUntil];
    }

    assert([batcherInputResultCapture fired]);
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

    [packet setCursorPosition:_leftPadding];
    [_batcherInput onNewPacket:packet fromProtocol:UDP];
}


@end