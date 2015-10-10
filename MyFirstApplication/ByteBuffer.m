//
//  ByteBuffer.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "ByteBuffer.h"

@implementation ByteBuffer

- (id)initWithSize:(uint)size {
    self = [super init];
    if (self) {
        _buffer = nil;
        _bufferMemorySize = 0;
        _bufferUsedSize = 0;
        _cursorPosition = 0;
        [self setMemorySize:size retaining:false];
    }
    return self;
}

- (id)initFromBuffer:(uint8_t *)sourceBuffer withSize:(uint)size {
    self = [super init];
    if (self) {
        _buffer = nil;
        _bufferMemorySize = 0;
        _bufferUsedSize = 0;
        _cursorPosition = 0;
        [self addVariableLengthData:sourceBuffer withLength:size includingPrefix:false];
    }
    return self;
}

- (id)initFromByteBuffer:(ByteBuffer *)buffer {
    self = [super init];
    if (self) {
        _buffer = nil;
        _bufferMemorySize = 0;
        _bufferUsedSize = 0;
        _cursorPosition = 0;
        [self addByteBuffer:buffer includingPrefix:false atPosition:0];
        _bufferUsedSize = [buffer bufferUsedSize];
        _cursorPosition = [buffer cursorPosition];
    }
    return self;
}

- (void)enforceBounds {
    // Ensure used size is within memory bounds.
    if (_bufferUsedSize > _bufferMemorySize) {
        _bufferUsedSize = _bufferMemorySize;
    }

    // Ensure cursor is within bounds.
    if (_cursorPosition > _bufferUsedSize) {
        _cursorPosition = _bufferUsedSize;
    }
}

- (void)setMemorySize:(uint)size retaining:(Boolean)isRetaining {
    if (size == _bufferMemorySize) {
        return;
    }

    uint8_t *oldBuffer = _buffer;
    uint amountToCopyFromOldBuffer;
    if (isRetaining) {
        if (_bufferUsedSize < size) {
            amountToCopyFromOldBuffer = _bufferUsedSize;
        } else {
            amountToCopyFromOldBuffer = size;
        }
    } else {
        amountToCopyFromOldBuffer = 0;
    }

    // Allocate new larger buffer.
    _buffer = malloc(sizeof(uint8_t) * size);

    // Copy old data in.
    if (oldBuffer != nil && amountToCopyFromOldBuffer > 0) {
        memcpy(_buffer, oldBuffer, amountToCopyFromOldBuffer);
        _bufferUsedSize = amountToCopyFromOldBuffer;
    } else {
        _bufferUsedSize = 0;
    }

    // Deallocate old buffer.
    free(oldBuffer);

    _bufferMemorySize = size;

    [self enforceBounds];
}

- (void)dealloc {
    free(_buffer);
}

- (void)setUsedSize:(uint)size {
    if (size > _bufferMemorySize) {
        [self setMemorySize:size retaining:true];
    }
    _bufferUsedSize = size;
    [self enforceBounds];
}

- (void)increaseMemorySize:(uint)size {
    if (size > _bufferMemorySize) {
        [self setMemorySize:size retaining:true];
    }
}

- (void)eraseFromPosition:(uint)position length:(uint)length {
    if (position > _bufferUsedSize || length == 0) {
        return;
    }

    // Simply need to decrease used size if there is nothing to shift down, i.e. we erase up to the end of the buffer.
    if (length + position < _bufferUsedSize) {
        // Destination begins at position
        // Source begins at position + length, straight after data to erase
        // Source ends at the end of all data currently in use, so that no useful data is lost in the shift
        memcpy(_buffer + position, (_buffer + position) + length, (_bufferUsedSize - position) - length);
        _bufferUsedSize -= length;
    } else {
        _bufferUsedSize = 0;
    }

    [self enforceBounds];
}

- (void)eraseFromCursor:(uint)length {
    [self eraseFromPosition:_cursorPosition length:length];

    // Change cursor
    if (length >= _cursorPosition) {
        _cursorPosition = 0;
    }
    else {
        _cursorPosition -= length;
    }
}

- (uint)getValue:(void *)dest fromPosition:(uint)position typeSize:(uint)typeSize {
    // Get the new end cursor position after getting
    uint endPosition = position + typeSize;

    // Prevent going out of bounds
    if (endPosition > _bufferUsedSize) {
        return position;
    }

    // Copy data into Return
    memcpy(dest, _buffer + position, typeSize);

    // Move cursor
    position = endPosition;

    return position;
}

- (uint)addValue:(void *)source atPosition:(uint)position typeSize:(uint)typeSize {
    // Get the new end position after adding
    uint endPosition = position + typeSize;

    // Increase size as necessary
    [self increaseMemorySize:endPosition];

    // Copy data into buffer.
    memcpy(_buffer + position, source, typeSize);

    return endPosition;
}

- (void)addValue:(void *)source typeSize:(uint)typeSize {
    [self setCursorPosition:[self addValue:source atPosition:_cursorPosition typeSize:typeSize]];
}

- (void)getValue:(void *)dest typeSize:(uint)typeSize {
    [self setCursorPosition:[self getValue:dest fromPosition:_cursorPosition typeSize:typeSize]];
}

- (uint)getUnsignedIntegerAtPosition:(uint)position {
    uint integer = 0;
    [self getValue:&integer fromPosition:position typeSize:sizeof(uint)];
    return integer;
}

- (uint)getUnsignedInteger {
    uint integer;
    [self getValue:&integer typeSize:sizeof(uint)];
    return integer;
}

- (void)addUnsignedInteger:(uint)integer atPosition:(uint)position {
    [self addValue:&integer atPosition:position typeSize:sizeof(uint)];
}

- (void)addUnsignedInteger:(uint)integer {
    [self addValue:&integer typeSize:sizeof(uint)];
}

- (void)setCursorPosition:(uint)newCursorPosition {
    [self increaseMemorySize:newCursorPosition];
    if (newCursorPosition > _bufferUsedSize) {
        _bufferUsedSize = newCursorPosition;
    }
    _cursorPosition = newCursorPosition;
}

- (void)moveCursorForwards:(uint)amount {
    [self setCursorPosition:_cursorPosition + amount];
}

// Unlike moveCursorForwards, will not resize buffer, instead
// will return false if it needed to (without moving cursor).
// Returns true if cursor moved successfully.
- (Boolean)moveCursorForwardsPassively:(uint)amount {
    uint newPosition = _cursorPosition + amount;
    if (newPosition > _bufferUsedSize) {
        return false;
    }
    _cursorPosition = newPosition;
    return true;
}

- (void)increaseUsedSize:(uint)amount {
    [self setUsedSize:amount + _bufferUsedSize];
}

- (Boolean)increaseUsedSizePassively:(uint)amount {
    uint newSize = amount + _bufferUsedSize;

    if (newSize > _bufferMemorySize) {
        return false;
    }
    _bufferUsedSize = newSize;

    return true;
}

- (uint)getUnreadDataFromCursor {
    return _bufferUsedSize - _cursorPosition;
}

- (uint)increaseMemoryIfUnusedAt:(uint)threshold to:(uint)newSize {
    if ([self getUnusedMemory] <= threshold) {
        [self setMemorySize:newSize retaining:true];
    }
    return 0;
}

- (uint)getUnusedMemory {
    return _bufferMemorySize - _bufferUsedSize;
}

- (uint)addVariableLengthData:(uint8_t *)data withLength:(uint)length includingPrefix:(Boolean)includePrefix atPosition:(uint)position {
    uint dataSize = sizeof(uint8_t) * length;
    uint newSize = position + dataSize;
    if (includePrefix) {
        newSize += sizeof(uint);
    }
    [self increaseMemorySize:newSize];
    if ([self bufferUsedSize] < newSize) {
        _bufferUsedSize = newSize;
    }
    if (includePrefix) {
        [self addUnsignedInteger:length atPosition:position];
        position += sizeof(uint);
    }
    memcpy(_buffer + position, data, dataSize);

    if (includePrefix) {
        dataSize += sizeof(uint);
    }
    return dataSize;
}

- (uint)addVariableLengthData:(uint8_t *)data withLength:(uint)length includingPrefix:(Boolean)includePrefix {
    uint dataSize = [self addVariableLengthData:data withLength:length includingPrefix:includePrefix atPosition:(_cursorPosition)];
    [self moveCursorForwards:dataSize];
    return dataSize;
}

- (uint)addVariableLengthData:(uint8_t *)data withLength:(uint)length {
    return [self addVariableLengthData:data withLength:length includingPrefix:true];
}

- (void)addByteBuffer:(ByteBuffer *)sourceBuffer includingPrefix:(Boolean)includePrefix atPosition:(uint)position startingFrom:(uint)startFrom {
    [self addVariableLengthData:sourceBuffer.buffer + startFrom withLength:sourceBuffer.bufferUsedSize - startFrom includingPrefix:includePrefix atPosition:position];
}

- (void)addByteBuffer:(ByteBuffer *)sourceBuffer includingPrefix:(Boolean)includePrefix atPosition:(uint)position {
    [self addByteBuffer:sourceBuffer includingPrefix:includePrefix atPosition:position startingFrom:0];
}

- (void)addByteBuffer:(ByteBuffer *)sourceBuffer includingPrefix:(Boolean)includePrefix {
    [self addVariableLengthData:sourceBuffer.buffer withLength:sourceBuffer.bufferUsedSize includingPrefix:includePrefix];
}

- (void)addByteBuffer:(ByteBuffer *)sourceBuffer {
    // note default of false is different to strings, we normally use this internally for buffering data.
    [self addByteBuffer:sourceBuffer includingPrefix:false];
}

- (void)addString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    const void *bytes = [data bytes];
    uint length = (uint) [data length];
    uint8_t *rawData = (uint8_t *) bytes;
    [self addVariableLengthData:rawData withLength:length];
}


- (id)getVariableLengthData:(id(^)(uint8_t *data, uint length))dataHandler withLength:(uint)length {
    uint prefixLength;
    if (length == 0) {
        prefixLength = sizeof(uint);
        if ([self getUnreadDataFromCursor] < prefixLength) {
            return nil;
        }

        length = [self getUnsignedIntegerAtPosition:_cursorPosition];
    } else {
        prefixLength = 0;
    }

    if ([self getUnreadDataFromCursor] < prefixLength + length) {
        return nil;
    }
    _cursorPosition += prefixLength;

    id result = dataHandler(_buffer + _cursorPosition, length);

    _cursorPosition += length;
    return result;
}

- (NSString *)getStringWithLength:(uint)length {
    return [self getVariableLengthData:^id(uint8_t *data, uint length) {
        return [[NSString alloc] initWithBytes:data
                                        length:length
                                      encoding:NSUTF8StringEncoding];
    }                       withLength:length];
}

- (NSString *)convertToString {
    return [[NSString alloc] initWithBytes:_buffer
                                    length:_bufferUsedSize
                                  encoding:NSUTF8StringEncoding];
}

- (NSString *)getString {
    return [self getStringWithLength:0];
}

- (ByteBuffer *)getByteBufferWithLength:(uint)length {
    return [self getVariableLengthData:^id(uint8_t *data, uint length) {
        return [[ByteBuffer alloc] initFromBuffer:data withSize:length];
    }                       withLength:length];
}

- (ByteBuffer *)getByteBuffer {
    return [self getByteBufferWithLength:0];
}

- (uint8_t *)getRawDataPtr {
    return _buffer;
}

- (void)clear {
    [self setCursorPosition:0];
    [self setUsedSize:0];
}

@end
