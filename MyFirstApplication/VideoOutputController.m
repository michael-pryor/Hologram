//
//  VideoOutputController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "VideoOutputController.h"
#import "ThrottledBlock.h"
#import "BatcherInput.h"
#import "EncodingPipe.h"
#import "TimedEventTracker.h"
#import "DelayedPipe.h"
#import "VideoCompression.h"

@implementation PacketToImageProcessor {
    id <NewImageDelegate> _newImageDelegate;
    VideoEncoding *_videoEncoder;
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate encoder:(VideoEncoding *)videoEncoder {
    self = [super init];
    if (self) {
        _newImageDelegate = newImageDelegate;
        _videoEncoder = videoEncoder;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    UIImage *image = [_videoEncoder getImageFromByteBuffer:packet];
    if (image == nil) {
        return;
    }

    [_newImageDelegate onNewImage:image];
}
@end


@implementation VideoOutputController {
    AVCaptureSession *_session;                       // Link to video input hardware.
    ThrottledBlock *_throttledBlock;                  // Control rate of video transmission over network.
    BatcherOutput *_batcherOutput;                    // Split up image into multiple packets for network.
    VideoEncoding *_videoEncoder;                     // Convert between network and image formats.
    EncodingPipe *_encodingPipeVideo;                 // Add appropriate prefix for transport over network.

    BatcherInput *_batcherInput;                      // Join up networked packets into one image.
    DelayedPipe *_delayedPipe;                        // Delay video output so that it syncs up with audio.

    id <NewPacketDelegate> _tcpNetworkOutputSession;   // For requesting slow down in network usage.

    TimedEventTracker *_slowDownThreshold;            // Decides when to ask for less network traffic.
    id <VideoSpeedNotifier> _videoSpeedNotifier;       // Notify of change in video frame rate.

    id<MediaDelayNotifier> _mediaDelayNotifier;       // Inform upstreams (e.g. GUI) of delay for debugging purposes.

}
- (id)initWithTcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier mediaDelayNotifier:(id<MediaDelayNotifier>) mediaDelayNotifier {
    self = [super init];
    if (self) {
         _tcpNetworkOutputSession = tcpNetworkOutputSession;


        _throttledBlock = [[ThrottledBlock alloc] initWithDefaultOutputFrequency:0 firingInitially:true];



        _videoEncoder = [[VideoEncoding alloc] initWithVideoCompression:[[VideoCompression alloc] init]];

        PacketToImageProcessor *p = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate encoder:_videoEncoder];

        // Delay video playback in order to sync up with audio.
        _delayedPipe = [[DelayedPipe alloc] initWithMinimumDelay:0 outputSession:p];

        _batcherInput = [[BatcherInput alloc] initWithOutputSession:_delayedPipe numChunksThreshold:1 timeoutMs:1000 performanceInformationDelegate:self];

        _encodingPipeVideo = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession prefixId:VIDEO_ID];

        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:_encodingPipeVideo leftPadding:sizeof(uint8_t)];

        _session = [_videoEncoder setupCaptureSessionWithDelegate:self];

        // 5 second of bad data.
        _slowDownThreshold = [[TimedEventTracker alloc] initWithMaxEvents:10 timePeriod:1];

        _videoSpeedNotifier = videoSpeedNotifier;

        _mediaDelayNotifier = mediaDelayNotifier;

    }
    return self;
}

- (void)start {
    NSLog(@"Starting video recording...");
    [_session startRunning];
    [_batcherInput reset];
}

- (void)stop {
    NSLog(@"Stopped video recording...");
    [_session stopRunning];
    [_batcherInput reset];
}

- (void)setNetworkOutputSessionTcp:(id <NewPacketDelegate>)tcp {
    NSLog(@"Updating video tcp network output sessions");
    _tcpNetworkOutputSession = tcp;
}

// Handle data from camera device and push out to network.
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    [_throttledBlock runBlock:^{
        // Send image as packet.
        ByteBuffer *rawBuffer = [[ByteBuffer alloc] init];

        if(![_videoEncoder addImage:sampleBuffer toByteBuffer:rawBuffer]) {
            return;
        }
        rawBuffer.cursorPosition = 0;

        [_batcherOutput onNewPacket:rawBuffer fromProtocol:UDP];
    }];
}

// Handle degrading network performance.
- (void)onNewPerformanceNotification:(float)percentageFilled {
    if (percentageFilled < 100.0 && [_slowDownThreshold increment]) {
        [self sendSlowdownRequest];
    }
}

- (void)sendSlowdownRequest {
    // Consider removing this; I don't think its particularly useful.
    /*NSLog(@"Requesting slow down in video");
    ByteBuffer *buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger:SLOW_DOWN_VIDEO];
    [_tcpNetworkOutputSession onNewPacket:buffer fromProtocol:TCP];*/
}

// Handle new data received on network to be pushed out to the user.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    [_batcherInput onNewPacket:packet fromProtocol:protocol];
}

- (void)slowSendRate {
    /*NSLog(@"Slowing send rate of video");
    [_throttledBlock slowRate];
    [_videoSpeedNotifier onNewVideoFrameFrequency:[_throttledBlock secondsFrequency]];*/
}

- (void)resetSendRate {
    /*NSLog(@"Resetting video send rate");
    [_throttledBlock reset];
    [_videoSpeedNotifier onNewVideoFrameFrequency:[_throttledBlock secondsFrequency]];*/
}

- (void)onMediaDelayNotified:(uint)delayMs {
    // NSLog(@"Should delay by %dms", delayMs);
    [_delayedPipe setMinimumDelay:((float)delayMs / 1000.0)];

    if (_mediaDelayNotifier != nil) {
        [_mediaDelayNotifier onMediaDelayNotified:delayMs];
    }
}


@end
