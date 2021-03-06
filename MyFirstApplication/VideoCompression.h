//
//  VideoCompression.h
//  Spawn
//
//  Created by Michael Pryor on 03/01/2016.
//
//

@import AVFoundation;

@protocol NewImageDelegate;
@protocol NewPacketDelegate;
@class ByteBuffer;

@interface VideoCompression : NSObject
- (id)init;

- (bool)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer toByteBuffer:(ByteBuffer *)buffer;

- (UIImage *)decodeByteBuffer:(ByteBuffer *)buffer;

- (UIImage *)convertSampleBufferToUiImage:(CMSampleBufferRef)sampleBuffer;

- (void)reset;
@end
