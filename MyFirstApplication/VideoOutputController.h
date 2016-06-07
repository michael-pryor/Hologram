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
#import "MediaShared.h"
#import "SequenceDecodingPipe.h"

@protocol NewImageDelegate
- (void)onNewImage:(UIImage *)image;
@end

@interface PacketToImageProcessor : NSObject <NewPacketDelegate>
@end


@interface VideoOutputController : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, NewPacketDelegate, SequenceGapNotification>
- (id)initWithUdpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDataLossNotifier:(id <MediaDataLossNotifier>)mediaDataLossNotifier leftPadding:(uint)leftPadding loopbackEnabled:(bool)loopbackEnabled;

- (void)startCapturing;

- (bool)stopCapturing;

- (void)resetInbound;

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate;

- (void)clearLocalImageDelegate;

- (void)setOutputSession:(id <NewPacketDelegate>)newPacketDelegate;

- (void)setVideoDelayMs:(uint)videoDelay;
@end
