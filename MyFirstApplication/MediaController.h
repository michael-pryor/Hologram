//
//  MediaController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 07/01/2015.
//
//
@import AVFoundation;

#import "InputSessionBase.h"
#import "ConnectionGovernorProtocol.h"
#import "Batch.h"
#import "VideoOutputController.h"
#import "SequenceDecodingPipe.h"
#import "BlockingQueueTemporal.h"

@protocol MediaOperator
- (void)startVideo;

- (void)stopVideo;

- (void)stopAudio;

- (void)startAudio;
@end

@interface MediaController : NSObject <NewPacketDelegate, SequenceGapNotification, TimeInQueueNotification, MediaOperator>
- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDataLossNotifier:(id <MediaDataLossNotifier>)mediaDataLossNotifier;

- (void)resetSendRate;

- (void)setNetworkOutputSessionUdp:(id <NewPacketDelegate>)udp;

- (void)stopAudio;

- (void)startAudio;

- (void)startVideo;

- (void)stopVideo;

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate;

- (void)clearLocalImageDelegate;

- (bool)isAudioPacket:(ByteBuffer*)buffer;

- (void)reduceMemoryUsage;
@end
