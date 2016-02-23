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

@protocol NewImageDelegate
- (void)onNewImage:(UIImage *)image;
@end

@interface PacketToImageProcessor : NSObject <NewPacketDelegate>
@end


@interface VideoOutputController : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, NewPacketDelegate, MediaDelayNotifier>
- (id)initWithUdpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDelayNotifier:(id <MediaDelayNotifier>)mediaDelayNotifier leftPadding:(uint)leftPadding;

- (void)startCapturing;

- (void)stopCapturing;

- (void)resetInbound;

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate;

- (void)clearLocalImageDelegate;
@end
