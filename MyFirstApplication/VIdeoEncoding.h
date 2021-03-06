//
//  Encoding.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

@import AVFoundation;

#import "ByteBuffer.h"

@class VideoCompression;
@class MemoryAwareObjectContainer;

@interface VideoEncoding : NSObject
- (id)initWithVideoCompression:(MemoryAwareObjectContainer *)videoCompression;

- (AVCaptureSession *)setupCaptureSessionWithDelegate:(id <AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;

- (bool)addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer *)buffer;

- (UIImage *)getImageFromByteBuffer:(ByteBuffer *)buffer;

- (UIImage *)convertSampleBufferToUiImage:(CMSampleBufferRef)sampleBuffer;

- (void)setFrameRate:(int)fps;
@end
