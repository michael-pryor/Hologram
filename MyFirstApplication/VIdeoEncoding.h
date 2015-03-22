//
//  Encoding.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

@import AVFoundation;
#import "ByteBuffer.h"

@interface VideoEncoding : NSObject
@property (readonly) uint bytesPerRow;
@property (readonly) uint height;
@property (readonly) uint totalSize;
@property (readonly) uint suggestedBatchSize;
@property (readonly) uint suggestedBatches;

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer;
- (AVCaptureSession *) setupCaptureSessionWithDelegate: (id<AVCaptureVideoDataOutputSampleBufferDelegate>) delegate;

- (void) addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer*)buffer;
- (UIImage*) getImageFromByteBuffer:(ByteBuffer*)buffer;
@end
