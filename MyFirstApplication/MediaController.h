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
#import "SoundPlayback.h"

@interface MediaController : NSObject <NewPacketDelegate, BatchPerformanceInformation, SoundPlaybackDelegate>
- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier tcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession;

- (void)sendSlowdownRequest;

- (void)resetSendRate;

- (void)setNetworkOutputSessionTcp:(id <NewPacketDelegate>)tcp Udp:(id <NewPacketDelegate>)udp;

- (void)stop;

- (void)start;
@end
