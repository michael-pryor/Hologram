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


- (id) init: (uint) p_bufferSize {
    self = [super init];
    if(self) {
        buffer = nil;
        bufferMemorySize = 0;
        bufferUsedSize = 0;
        cursorPosition = 0;
        [self setBufferSize: p_bufferSize retaining: false];
    }
    return self;
}

- (void) setBufferSize: (uint) size retaining: (Boolean) isRetaining {
    if(size == bufferUsedSize) {
        return;
    }
    
    if(size > bufferMemorySize) {
        uint8_t * oldBuffer = buffer;
        uint oldBufferSize = bufferUsedSize;
        
        // Allocate new larger buffer.
        buffer = malloc(sizeof(uint8_t) * size);
        
        // Copy old data in.
        if(isRetaining && oldBuffer != nil && oldBufferSize > 0) {
            memcpy(buffer, oldBuffer, oldBufferSize);
        } else {
            cursorPosition = 0;
        }
        
        // Deallocate old buffer.
        free(oldBuffer);
        
        bufferMemorySize = size;
    }
    
    // We can freely expand (or reduce), we have enough memory.
    bufferUsedSize = size;
    
    // Ensure cursor is within bounds.
    if(cursorPosition > bufferUsedSize) {
        cursorPosition = bufferUsedSize - 1;
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
    }
    
    // Change used size
    bufferUsedSize -= length;
    
    // Change cursor
    if(length >= cursorPosition) {
        cursorPosition = 0;
    }
    else {
        cursorPosition -= length;
    }
}

- (void) eraseFromCursor: (uint) length {
    [self eraseFromPosition: cursorPosition length: length];
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

- (uint) addValue: (void*) source toPosition: (uint) position typeSize: (uint) typeSize {
    // Get the new end position after adding
    uint endPosition = position + typeSize;
        
    // Increase size as necessary
    [self setBufferSize: endPosition retaining: true];

    // Copy data into buffer.
    memcpy(buffer + position, source, typeSize);
    
    return endPosition;
}

- (uint) addValue: (void*) source typeSize: (uint) typeSize {
    cursorPosition = [self addValue:source toPosition:cursorPosition typeSize:typeSize];
    return cursorPosition;
}

- (uint) getValue: (void*) dest typeSize: (uint) typeSize {
    cursorPosition = [self getValue:dest fromPosition:cursorPosition typeSize:typeSize];
    return cursorPosition;
}

- (uint) getUnsignedIntegerFromPosition: (uint) position {
    uint integer;
    [self getValue:&integer fromPosition:position typeSize:sizeof(uint)];
    return integer;
}

- (uint) getUnsignedInteger {
    uint integer;
    [self getValue:&integer typeSize:sizeof(uint)];
    return integer;
}

- (void) addUnsignedInteger: (uint) integer AtPosition: (uint) position {
    [self addValue:&integer toPosition:position typeSize:sizeof(uint)];
}

- (void) addUnsignedInteger: (uint) integer {
    [self addValue:&integer typeSize:sizeof(uint)];
}

- (void) setCursorPosition:(uint)newCursorPosition {
    if(newCursorPosition > bufferUsedSize) {
        cursorPosition = bufferUsedSize;
    } else {
        cursorPosition = newCursorPosition;
    }
}


@end
