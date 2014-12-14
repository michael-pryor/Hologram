//
//  ByteBuffer.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "ByteBuffer.h"
#include <stdlib.h>

@implementation ByteBuffer
@synthesize buffer;
@synthesize bufferMemorySize;
@synthesize bufferUsedSize;
@synthesize cursorPosition;


- (id) initWithSize: (uint)p_bufferSize {
    self = [super init];
    if(self) {
        buffer = nil;
        bufferMemorySize = 0;
        bufferUsedSize = 0;
        cursorPosition = 0;
        [self setMemorySize: p_bufferSize retaining: false];
    }
    return self;
}

- (id) initFromBuffer: (uint8_t*)p_buffer withSize: (uint)p_bufferSize {
    self = [super init];
    if(self) {
        buffer = nil;
        bufferMemorySize = 0;
        bufferUsedSize = 0;
        cursorPosition = 0;
        [self addData:p_buffer withLength:p_bufferSize includingPrefix:false];
    }
    return self;
}

- (void) enforceBounds {
    // Ensure used size is within memory bounds.
    if(bufferUsedSize > bufferMemorySize) {
        bufferUsedSize = bufferMemorySize;
    }

    // Ensure cursor is within bounds.
    if(cursorPosition > bufferUsedSize) {
        cursorPosition = bufferUsedSize;
    }
}

- (void) setMemorySize: (uint)size retaining: (Boolean)isRetaining {
    if(size == bufferMemorySize) {
        return;
    }
    
    uint8_t * oldBuffer = buffer;
    uint amountToCopyFromOldBuffer;
    if(isRetaining) {
        if(bufferUsedSize < size) {
            amountToCopyFromOldBuffer = bufferUsedSize;
        } else {
            amountToCopyFromOldBuffer = size;
        }
    } else {
        amountToCopyFromOldBuffer = 0;
    }
    
    // Allocate new larger buffer.
    buffer = malloc(sizeof(uint8_t) * size);
    
    // Copy old data in.
    if(oldBuffer != nil && amountToCopyFromOldBuffer > 0) {
        memcpy(buffer, oldBuffer, amountToCopyFromOldBuffer);
        bufferUsedSize = amountToCopyFromOldBuffer;
    } else {
        bufferUsedSize = 0;
    }
    
    // Deallocate old buffer.
    free(oldBuffer);
    
    bufferMemorySize = size;
    
    [self enforceBounds];
}

- (void) setUsedSize: (uint)size {
    bufferUsedSize = size;
    [self enforceBounds];
}

- (void) increaseMemorySize: (uint)size {
    if(size > bufferMemorySize) {
        [self setMemorySize: size retaining:true];
    }
}

- (void) eraseFromPosition: (uint) position length: (uint) length {
    if(position > bufferUsedSize || length == 0) {
        return;
    }
    
    // Simply need to decrease used size if there is nothing to shift down, i.e. we erase up to the end of the buffer.
    if(length + position < bufferUsedSize) {
        // Destination begins at position
        // Source begins at position + length, straight after data to erase
        // Source ends at the end of all data currently in use, so that no useful data is lost in the shift
        memcpy(buffer + position,(buffer + position) + length, (bufferUsedSize - position) - length);
        bufferUsedSize -= length;
    } else {
        bufferUsedSize = 0;
    }
    
    [self enforceBounds];
}

- (void) eraseFromCursor: (uint) length {
    [self eraseFromPosition: cursorPosition length: length];
    
    // Change cursor
    if(length >= cursorPosition) {
        cursorPosition = 0;
    }
    else {
        cursorPosition -= length;
    }
}

- (uint) getValue: (void*) dest fromPosition: (uint) position typeSize: (uint) typeSize {
    // Get the new end cursor position after getting
    uint endPosition = position + typeSize;
        
    // Prevent going out of bounds
    if(endPosition > bufferUsedSize) {
        return position;
    }
    
    // Copy data into Return
    memcpy(dest, buffer + position, typeSize);
    
    // Move cursor
    position = endPosition;

    return position;
}

- (uint) addValue: (void*) source atPosition: (uint) position typeSize: (uint) typeSize {
    // Get the new end position after adding
    uint endPosition = position + typeSize;
        
    // Increase size as necessary
    [self increaseMemorySize: endPosition];

    // Copy data into buffer.
    memcpy(buffer + position, source, typeSize);
    
    return endPosition;
}

- (void) addValue: (void*) source typeSize: (uint) typeSize {
    [self setCursorPosition: [self addValue:source atPosition:cursorPosition typeSize:typeSize]];
}

- (void) getValue: (void*) dest typeSize: (uint) typeSize {
    [self setCursorPosition: [self getValue:dest fromPosition:cursorPosition typeSize:typeSize]];
}

- (uint) getUnsignedIntegerAtPosition: (uint) position {
    uint integer = 0;
    [self getValue:&integer fromPosition:position typeSize:sizeof(uint)];
    return integer;
}

- (uint) getUnsignedInteger {
    uint integer;
    [self getValue:&integer typeSize:sizeof(uint)];
    return integer;
}

- (void) addUnsignedInteger: (uint) integer atPosition: (uint) position {
    [self addValue:&integer atPosition:position typeSize:sizeof(uint)];
}

- (void) addUnsignedInteger: (uint) integer {
    [self addValue:&integer typeSize:sizeof(uint)];
}

- (void) setCursorPosition:(uint)newCursorPosition {
    [self increaseMemorySize:newCursorPosition];
    if(newCursorPosition > bufferUsedSize) {
        bufferUsedSize = newCursorPosition;
    }
    cursorPosition = newCursorPosition;
}

- (void) moveCursorForwards:(uint)amount {
    [self setCursorPosition:cursorPosition + amount];
}

// Unlike moveCursorForwards, will not resize buffer, instead
// will return false if it needed to (without moving cursor).
// Returns true if cursor moved successfully.
- (Boolean) moveCursorForwardsPassively:(uint)amount {
    uint newPosition = cursorPosition + amount;
    if(newPosition > bufferUsedSize) {
        return false;
    }
    cursorPosition = newPosition;
    return true;
}

- (void) increaseUsedSize: (uint)amount {
 	[self setUsedSize:amount + bufferUsedSize];
}

- (Boolean) increaseUsedSizePassively: (uint)amount {
	uint newSize = amount + bufferUsedSize;
    
    if(newSize > bufferMemorySize) {
        return false;
    }
    bufferUsedSize = newSize;
    
    return true;
}
- (uint) getUnreadDataFromCursor {
    return bufferUsedSize - cursorPosition;
}

- (uint) increaseMemoryIfUnusedAt: (uint)threshold to: (uint)newSize{
    if([self getUnusedMemory] <= threshold) {
        [self setMemorySize:newSize retaining:true];
    }
    return 0;
}
- (uint) getUnusedMemory {
    return bufferMemorySize - bufferUsedSize;
}

- (void) addData: (uint8_t*)data withLength: (uint)length includingPrefix: (Boolean)includePrefix {
    uint dataSize = sizeof(uint8_t) * length;
    uint newSize = cursorPosition + dataSize;
    if(includePrefix) {
        newSize += sizeof(uint);
    }
    [self increaseMemorySize:newSize];
    if(includePrefix) {
        [self addUnsignedInteger:length];
    }
    memcpy(buffer + cursorPosition, data, dataSize);
    [self moveCursorForwards:dataSize];
}

- (void) addData: (uint8_t*)data withLength: (uint)length {
    [self addData:data withLength:length includingPrefix:true];
}

- (void) addByteBuffer: (ByteBuffer*)p_buffer includingPrefix: (Boolean)includePrefix {
    [self addData:p_buffer.buffer withLength:p_buffer.bufferUsedSize includingPrefix:includePrefix];
}

- (void) addByteBuffer: (ByteBuffer*)p_buffer {
    // note default of false is different to strings, we normally use this internally for buffering data.
    [self addByteBuffer:p_buffer includingPrefix:false];
}

- (void) addString: (NSString*) string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    const void *bytes = [data bytes];
    uint length = (uint)[data length];
    uint8_t * rawData = (uint8_t*)bytes;
    [self addData:rawData withLength:length];
}


- (id) getVariableLengthData:(id(^)(uint8_t* data, uint length))dataHandler withLength: (uint)length{
    if([self getUnreadDataFromCursor] < sizeof(uint)) {
        return nil;
    }
    
    uint prefixLength;
    if(length == 0) {
    	length = [self getUnsignedIntegerAtPosition:cursorPosition];
        prefixLength = sizeof(uint);
    } else {
        prefixLength = 0;
    }
    
    if([self getUnreadDataFromCursor] < prefixLength + length) {
        return nil;
    }
    cursorPosition += prefixLength;
    
    id result = dataHandler(buffer + cursorPosition, length);
    
    cursorPosition += length;
    return result;
}

- (NSString*)getStringWithLength: (uint) length {
    return [self getVariableLengthData:^id(uint8_t* data, uint length) {
        return [[NSString alloc] initWithBytes:data
                                 length:length
                                 encoding:NSUTF8StringEncoding];
    } withLength: length];
}

- (NSString*)convertToString {
    return [[NSString alloc] initWithBytes:buffer
                             length:bufferUsedSize
                             encoding:NSUTF8StringEncoding];
}

- (NSString*)getString {
    return [self getStringWithLength:0];
}

- (ByteBuffer*)getByteBufferWithLength: (uint) length {
    return [self getVariableLengthData:^id(uint8_t* data, uint length) {
        return [[ByteBuffer alloc] initFromBuffer:data withSize:length];
    } withLength: length];
}

- (ByteBuffer*)getByteBuffer {
    return [self getByteBufferWithLength:0];
}

@end
