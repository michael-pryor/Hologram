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

@interface MediaController : NSObject <NewPacketDelegate, SequenceGapNotification>
- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDelayNotifier:(id <MediaDelayNotifier>)mediaDelayNotifier;

- (void)resetSendRate;

- (void)setNetworkOutputSessionUdp:(id <NewPacketDelegate>)udp;

- (void)stop;

- (void)start;

- (void)startVideo;

- (void)stopVideo;

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate;

- (void)clearLocalImageDelegate;
@end
