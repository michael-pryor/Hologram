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
#import "BatcherOutput.h"

@protocol NewImageDelegate
- (void)onNewImage:(UIImage *)image;
@end

@protocol VideoSpeedNotifier
- (void)onNewVideoFrameFrequency:(CFAbsoluteTime)secondsFrequency;
@end

@interface PacketToImageProcessor : NSObject <NewPacketDelegate>
@end


@interface VideoOutputController : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, BatchPerformanceInformation, NewPacketDelegate>
- (id)initWithTcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier batchNumberListener:(id <BatchNumberListener>)batchNumberListener;

- (void)slowSendRate;

- (void)resetSendRate;

- (void)sendSlowdownRequest;

- (void)setNetworkOutputSessionTcp:(id <NewPacketDelegate>)tcp;

- (void)start;

- (void)stop;
@end
