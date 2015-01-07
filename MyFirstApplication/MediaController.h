//
//  MediaController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 07/01/2015.
//
//
#import "InputSession.h"
@import AVFoundation;

@protocol NewImageDelegate
- (void)onNewImage: (UIImage*) image;
@end

@interface MediaController : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate, NewPacketDelegate>
- (id)initWithImageDelegate: (id<NewImageDelegate>)newImageDelegate andwithNetworkOutputSession: (OutputSession*)networkOutputSession;
- (void) startCapturing;
- (void) stopCapturing;
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
- (void)onNewPacket: (ByteBuffer *)packet;
@end
