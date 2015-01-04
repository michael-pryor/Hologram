//
//  MediaByteBuffer.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "ByteBuffer.h"
@import AVFoundation;

@interface MediaByteBuffer : ByteBuffer
- (void) addImage: (CMSampleBufferRef) image;
@end
