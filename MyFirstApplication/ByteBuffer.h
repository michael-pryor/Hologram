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

- (void) setBufferSize: (uint) size retaining: (Boolean) isRetaining;
- (void) eraseFromPosition: (uint) position length: (uint) length;
- (void) eraseFromCursor: (uint) length;
- (uint) getUnsignedIntegerFromPosition: (uint) position;
- (uint) getUnsignedInteger;
- (void) addUnsignedInteger: (uint) integer AtPosition: (uint) position;
- (void) addUnsignedInteger: (uint) integer;

- (id) init: (uint) p_bufferSize;
@end
