//
//  VideoOutputController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

@import AVFoundation;

#import <Foundation/Foundation.h>
#import "Batch.h"
#import "PipelineProcessor.h"
#import "VIdeoEncoding.h"
#import "NetworkOperations.h"

@protocol NewImageDelegate
- (void)onNewImage: (UIImage*) image;
@end

@interface PacketToImageProcessor : NSObject<NewPacketDelegate>
@end

@interface VideoOutputController : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate, BatchPerformanceInformation, NewPacketDelegate>
- (id)initWithTcpNetworkOutputSession:(id<NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id<NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id<NewImageDelegate>)newImageDelegate;
- (void)slowSendRate;
@end
