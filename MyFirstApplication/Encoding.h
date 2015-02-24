//
//  Encoding.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

@import AVFoundation;

@interface Encoding : NSObject
@property (readonly) uint bytesPerRow;
@property (readonly) uint height;
@property (readonly) uint totalSize;
@property (readonly) uint suggestedBatchSize;
@property (readonly) uint suggestedBatches;

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer;
- (AVCaptureSession *) setupCaptureSessionWithDelegate: (id<AVCaptureVideoDataOutputSampleBufferDelegate>) delegate;
@end
