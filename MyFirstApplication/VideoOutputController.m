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
#import "BatcherOutput.h"
#import "EncodingPipe.h"


@implementation PacketToImageProcessor {
    id<NewImageDelegate> _newImageDelegate;
    VideoEncoding* _videoEncoder;
}

- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate encoder:(VideoEncoding*)videoEncoder {
    self = [super init];
    if(self) {
        _newImageDelegate = newImageDelegate;
        _videoEncoder = videoEncoder;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    UIImage *image = [_videoEncoder getImageFromByteBuffer:packet];
    if(image == nil) {
        return;
    }
    
    [_newImageDelegate onNewImage: image];
}
@end


@implementation VideoOutputController {
    AVCaptureSession* _session;                       // Link to video input hardware.
    ThrottledBlock* _throttledBlock;                  // Control rate of video transmission over network.
    BatcherOutput* _batcherOutput;                    // Split up image into multiple packets for network.
    VideoEncoding* _videoEncoder;                     // Convert between network and image formats.
    EncodingPipe* _encodingPipeVideo;                 // Add appropriate prefix for transport over network.
    
    BatcherInput* _batcherInput;                      // Join up networked packets into one image.
    id<NewImageDelegate> _newImageDelegate;           // Push to users' screens.
    
    id<NewPacketDelegate> _tcpNetworkOutputSession;   // For requesting slow down in network usage.
}
- (id)initWithTcpNetworkOutputSession:(id<NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id<NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id<NewImageDelegate>)newImageDelegate {
    self = [super init];
    if(self) {
        _newImageDelegate = newImageDelegate;
        
        _videoEncoder = [[VideoEncoding alloc] init];
        
        _throttledBlock = [[ThrottledBlock alloc] initWithDefaultOutputFrequency:0.1 firingInitially:true];
        
        PacketToImageProcessor * p = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate encoder:_videoEncoder];
        
        _encodingPipeVideo = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession andPrefixId:VIDEO_ID];
        
        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:_encodingPipeVideo andChunkSize:[_videoEncoder suggestedBatchSize] withLeftPadding:sizeof(uint) includeTotalChunks:true];
        
        _batcherInput = [[BatcherInput alloc] initWithOutputSession:p chunkSize:[_videoEncoder suggestedBatchSize] numChunks:0 andNumChunksThreshold:0 andTimeoutMs:1000 andPerformanceInformaitonDelegate:self];
        
        _session = [_videoEncoder setupCaptureSessionWithDelegate: self];
                
        NSLog(@"Starting recording...");
        [_session startRunning];
    }
    return self;
}

// Handle data from camera device and push out to network.
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    [_throttledBlock runBlock:^ {
        // Send image as packet.
        ByteBuffer* rawBuffer = [[ByteBuffer alloc] init];
        
        [_videoEncoder addImage:sampleBuffer toByteBuffer:rawBuffer];
        rawBuffer.cursorPosition = 0;
        
        [_batcherOutput onNewPacket:rawBuffer fromProtocol:UDP];
    }];
}

// Handle degrading network performance.
- (void)onNewOutput:(float)percentageFilled {
    if(percentageFilled < 100.0) {
        NSLog(@"Requesting slow down in video");
        ByteBuffer* buffer = [[ByteBuffer alloc] init];
        [buffer addUnsignedInteger:SLOW_DOWN_VIDEO];
        [_tcpNetworkOutputSession onNewPacket:buffer fromProtocol:TCP];
    }
}

// Handle new data received on network to be pushed out to the user.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    [_batcherInput onNewPacket:packet fromProtocol:protocol];
}

@end
