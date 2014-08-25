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

- (void)testExample
{
    ByteBuffer * buffer = [[ByteBuffer alloc] init: 1];
    [buffer addUnsignedInteger:5];
    [buffer addUnsignedInteger:10];
    [buffer addUnsignedInteger:123456];
    
    assert([buffer cursorPosition] == sizeof(uint) * 3);
    
    [buffer setCursorPosition: 0];
    uint result;
    result = [buffer getUnsignedInteger];
    assert(result == 5);
    
    result = [buffer getUnsignedInteger];
    assert(result == 10);
    
    result = [buffer getUnsignedInteger];
    assert(result == 123456);
}

@end
