//
//  MediaController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 07/01/2015.
//
//
@import AVFoundation;
#import "InputSessionBase.h"
#import "ConnectionManagerProtocol.h"

@protocol NewImageDelegate
- (void)onNewImage: (UIImage*) image;
@end

@interface PacketToImageProcessor : NSObject<NewPacketDelegate>
@end

@interface MediaController : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate, NewPacketDelegate, ConnectionStatusDelegateProtocol>
- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate andwithNetworkOutputSession:(id<NewPacketDelegate>)networkOutputSession;
- (void)startCapturing;
- (void)stopCapturing;
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
@end
