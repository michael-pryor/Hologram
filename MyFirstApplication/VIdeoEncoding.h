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

@interface VideoEncoding : NSObject
- (id)initWithVideoCompression:(VideoCompression*)videoCompression;

- (AVCaptureSession *)setupCaptureSessionWithDelegate:(id <AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;

- (bool)addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer *)buffer;

- (UIImage *)getImageFromByteBuffer:(ByteBuffer *)buffer;
@end
