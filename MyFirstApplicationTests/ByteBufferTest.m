//
//  ByteBufferTest.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import <XCTest/XCTest.h>
#import "ByteBuffer.h"

@interface ByteBufferTest : XCTestCase

@end

@implementation ByteBufferTest

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testBuffer
{
    ByteBuffer * buffer = [[ByteBuffer alloc] initWithSize: 1];
    assert(buffer.cursorPosition == 0);
    assert(buffer.bufferUsedSize == 0);
    assert(buffer.bufferMemorySize == 1);
    
    [buffer addUnsignedInteger:5];
    
    assert(buffer.cursorPosition == sizeof(uint));
    assert(buffer.bufferUsedSize == sizeof(uint));
    assert(buffer.bufferMemorySize == sizeof(uint));
    
    [buffer addUnsignedInteger:10];
    
    assert(buffer.cursorPosition == sizeof(uint)*2);
    assert(buffer.bufferUsedSize == sizeof(uint)*2);
    assert(buffer.bufferMemorySize == sizeof(uint)*2);
    
    [buffer addUnsignedInteger:123456];
    
    assert(buffer.cursorPosition == sizeof(uint)*3);
    assert(buffer.bufferUsedSize == sizeof(uint)*3);
    assert(buffer.bufferMemorySize == sizeof(uint)*3);
    
    [buffer setCursorPosition: 0];
    
    assert(buffer.cursorPosition == 0);
    assert(buffer.bufferUsedSize == sizeof(uint)*3);
    assert(buffer.bufferMemorySize == sizeof(uint)*3);
    
    uint result;
    result = [buffer getUnsignedInteger];
    assert(result == 5);
    assert(buffer.cursorPosition == sizeof(uint));
    assert(buffer.bufferUsedSize == sizeof(uint)*3);
    assert(buffer.bufferMemorySize == sizeof(uint)*3);
    
    result = [buffer getUnsignedInteger];
    assert(result == 10);
    assert(buffer.cursorPosition == sizeof(uint)*2);
    assert(buffer.bufferUsedSize == sizeof(uint)*3);
    assert(buffer.bufferMemorySize == sizeof(uint)*3);
    
    result = [buffer getUnsignedInteger];
    assert(result == 123456);
    assert(buffer.cursorPosition == sizeof(uint)*3);
    assert(buffer.bufferUsedSize == sizeof(uint)*3);
    assert(buffer.bufferMemorySize == sizeof(uint)*3);
    
    [buffer setCursorPosition:0];
    [buffer addString: @"hello world"];
    assert(buffer.cursorPosition == sizeof(uint)+11);
    assert(buffer.bufferUsedSize == sizeof(uint)+11);
    assert(buffer.bufferMemorySize == sizeof(uint)+11);
    
    [buffer addString: @"hello universe!"];
    assert(buffer.cursorPosition == sizeof(uint)+11+sizeof(uint)+15);
    assert(buffer.bufferUsedSize == sizeof(uint)+11+sizeof(uint)+15);
    assert(buffer.bufferMemorySize == sizeof(uint)+11+sizeof(uint)+15);
    
    [buffer setCursorPosition:0];
    assert(buffer.cursorPosition == 0);
    assert(buffer.bufferUsedSize == sizeof(uint)+11+sizeof(uint)+15);
    assert(buffer.bufferMemorySize == sizeof(uint)+11+sizeof(uint)+15);
    
    
    NSString * strResult;
    strResult = [buffer getString];
    assert([strResult isEqualToString:@"hello world"]);
    assert(buffer.cursorPosition == sizeof(uint)+11);
    assert(buffer.bufferUsedSize == sizeof(uint)+11+sizeof(uint)+15);
    assert(buffer.bufferMemorySize == sizeof(uint)+11+sizeof(uint)+15);
    
    strResult = [buffer getString];
    assert([strResult isEqualToString:@"hello universe!"]);
    assert(buffer.cursorPosition == sizeof(uint)+11+sizeof(uint)+15);
    assert(buffer.bufferUsedSize == sizeof(uint)+11+sizeof(uint)+15);
    assert(buffer.bufferMemorySize == sizeof(uint)+11+sizeof(uint)+15);
}

@end
