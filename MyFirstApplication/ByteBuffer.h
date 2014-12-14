//
//  ByteBuffer.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import <Foundation/Foundation.h>

@interface ByteBuffer : NSObject
@property (readonly) uint8_t * buffer;
@property (readonly) uint bufferMemorySize;
@property (readonly) uint bufferUsedSize;
@property (nonatomic) uint cursorPosition;

- (void) setUsedSize: (uint)size;
- (void) setMemorySize: (uint)size retaining: (Boolean)isRetaining;
- (void) increaseMemorySize: (uint)size;
- (void) eraseFromPosition: (uint)position length: (uint)length;
- (void) eraseFromCursor: (uint)length;
- (uint) getUnsignedIntegerAtPosition: (uint)position;
- (uint) getUnsignedInteger;
- (void) addUnsignedInteger: (uint)integer atPosition: (uint)position;
- (void) addUnsignedInteger: (uint)integer;

- (uint) increaseMemoryIfUnusedAt: (uint)threshold to: (uint)newSize;
- (uint) getUnusedMemory;
- (uint) getUnreadDataFromCursor;
- (void) moveCursorForwards:(uint)amount;
- (Boolean) moveCursorForwardsPassively:(uint)amount;
- (void) setCursorPosition:(uint)newCursorPosition;

- (void) addString: (NSString*)string;
- (void) addData: (uint8_t*)data withLength: (uint)length includingPrefix: (Boolean)includePrefix;
- (void) addData: (uint8_t*)data withLength: (uint)length;
- (void) addByteBuffer: (ByteBuffer*)p_buffer includingPrefix: (Boolean)includePrefix;
- (void) addByteBuffer: (ByteBuffer*)p_buffer;
- (NSString*) getString;
- (ByteBuffer*) getByteBuffer;
- (NSString*)getStringWithLength: (uint) length;
- (ByteBuffer*)getByteBufferWithLength: (uint) length;

- (NSString*)convertToString;

- (id) initWithSize: (uint) p_bufferSize;
- (id) initFromBuffer: (uint8_t*)p_buffer withSize: (uint)p_bufferSize;

- (void) increaseUsedSize: (uint)amount;
- (Boolean) increaseUsedSizePassively: (uint)amount;
@end
