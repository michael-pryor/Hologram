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
#import "Batch.h"
#import "VideoOutputController.h"



@interface MediaController : NSObject<NewPacketDelegate, ConnectionStatusDelegateProtocol, BatchPerformanceInformation>
- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate tcpNetworkOutputSession:(id<NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id<NewPacketDelegate>)udpNetworkOutputSession;
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
@end
