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
@property(readonly) uint suggestedBatchSize;
- (id)initWithVideoCompression:(VideoCompression*)videoCompression;

- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (AVCaptureSession *)setupCaptureSessionWithDelegate:(id <AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;

- (void)addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer *)buffer;

- (UIImage *)getImageFromByteBuffer:(ByteBuffer *)buffer;
@end
