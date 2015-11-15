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
    id <NewImageDelegate> _newImageDelegate;           // Push to users' screens.

    id <NewPacketDelegate> _tcpNetworkOutputSession;   // For requesting slow down in network usage.

    TimedEventTracker *_slowDownThreshold;            // Decides when to ask for less network traffic.
    id <VideoSpeedNotifier> _videoSpeedNotifier;       // Notify of change in video frame rate.

}
- (id)initWithTcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier batchNumberListener:(id <BatchNumberListener>)batchNumberListener {
    self = [super init];
    if (self) {
        _newImageDelegate = newImageDelegate;
        _tcpNetworkOutputSession = tcpNetworkOutputSession;

        _videoEncoder = [[VideoEncoding alloc] init];

        _throttledBlock = [[ThrottledBlock alloc] initWithDefaultOutputFrequency:0.1 firingInitially:true];

        PacketToImageProcessor *p = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate encoder:_videoEncoder];

        // Put a delayed interaction between Network -> BatcherInput -> DELAYED INTERACTION -> PacketToImageProcessor
        // This delayed interaction receives:
        // - Batch ID of packet being passed from BatcherInput.
        // - Batch ID of last processed audio data.
        //
        // And delays the video packet until its ID matches (give or take some number to line them up) the ID of the audio frame that was last played.

        _encodingPipeVideo = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession prefixId:VIDEO_ID];

        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:_encodingPipeVideo chunkSize:[_videoEncoder suggestedBatchSize] leftPadding:sizeof(uint) includeTotalChunks:true batchNumberListener:batchNumberListener];

        _batcherInput = [[BatcherInput alloc] initWithOutputSession:p chunkSize:[_videoEncoder suggestedBatchSize] numChunks:0 andNumChunksThreshold:1 andTimeoutMs:1000 andPerformanceInformaitonDelegate:self];

        _session = [_videoEncoder setupCaptureSessionWithDelegate:self];

        // 5 second of bad data.
        _slowDownThreshold = [[TimedEventTracker alloc] initWithMaxEvents:10 timePeriod:1];

        _videoSpeedNotifier = videoSpeedNotifier;

    }
    return self;
}

- (void)start {
    NSLog(@"Starting video recording...");
    [_session startRunning];
}

- (void)stop {
    NSLog(@"Stopped video recording...");
    [_session stopRunning];
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

        [_videoEncoder addImage:sampleBuffer toByteBuffer:rawBuffer];
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
    NSLog(@"Requesting slow down in video");
    ByteBuffer *buffer = [[ByteBuffer alloc] init];
    [buffer addUnsignedInteger:SLOW_DOWN_VIDEO];
    [_tcpNetworkOutputSession onNewPacket:buffer fromProtocol:TCP];
}

// Handle new data received on network to be pushed out to the user.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    [_batcherInput onNewPacket:packet fromProtocol:protocol];
}

- (void)slowSendRate {
    NSLog(@"Slowing send rate of video");
    [_throttledBlock slowRate];
    [_videoSpeedNotifier onNewVideoFrameFrequency:[_throttledBlock secondsFrequency]];
}

- (void)resetSendRate {
    NSLog(@"Resetting video send rate");
    [_throttledBlock reset];
    [_videoSpeedNotifier onNewVideoFrameFrequency:[_throttledBlock secondsFrequency]];
}


@end
