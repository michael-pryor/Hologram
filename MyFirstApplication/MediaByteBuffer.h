//
//  MediaByteBuffer.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "ByteBuffer.h"
@import AVFoundation;

@interface MediaByteBuffer : NSObject
- (id) initFromBuffer: (ByteBuffer*)byteBuffer;
- (void) addImage: (CMSampleBufferRef) image;
- (UIImage*) getImage;
@end
