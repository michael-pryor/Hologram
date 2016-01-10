//
//  VideoCompression.h
//  Spawn
//
//  Created by Michael Pryor on 03/01/2016.
//
//

@import AVFoundation;
#import <Foundation/Foundation.h>

@protocol NewImageDelegate;

@interface VideoCompression : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate>
- (id)init;
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
- (id) initWithNewImageDelegate:(id <NewImageDelegate>)newImageDelegate;
@end
