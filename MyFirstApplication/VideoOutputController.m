//
//  VideoOutputController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "VideoOutputController.h"
#import "BatcherInput.h"
#import "EncodingPipe.h"
#import "DelayedPipe.h"
#import "VideoCompression.h"
#import "Timer.h"
#import "DecodingPipe.h"
#import "TimedCounterLogging.h"

@implementation PacketToImageProcessor {
    id <NewImageDelegate> _newImageDelegate;
    VideoEncoding *_videoEncoder;
    TimedCounterLogging *_videoDataUsageCounter;
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate encoder:(VideoEncoding *)videoEncoder {
    self = [super init];
    if (self) {
        _newImageDelegate = newImageDelegate;
        _videoEncoder = videoEncoder;
        _videoDataUsageCounter = [[TimedCounterLogging alloc] initWithDescription:@"Video Compressed Inbound"];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (_newImageDelegate == nil) {
        return;
    }

    [_videoDataUsageCounter incrementBy:[packet bufferUsedSize]];
    UIImage *image = [_videoEncoder getImageFromByteBuffer:packet];
    if (image == nil) {
        return;
    }

    [_newImageDelegate onNewImage:image];
}

- (void)setNewImageDelegate:(id <NewImageDelegate>)newImageDelegate {
    _newImageDelegate = newImageDelegate;
}
@end


@implementation VideoOutputController {
    AVCaptureSession *_captureSession;                       // Link to video input hardware.
    BatcherOutput *_batcherOutput;                    // Split up image into multiple packets for network.
    VideoEncoding *_videoEncoder;                     // Convert between network and image formats.
    EncodingPipe *_encodingPipeVideo;                 // Add appropriate prefix for transport over network.
    PacketToImageProcessor *_packetToImageProcessor; // Convert compressed network packets into UIImage objects.

    BatcherInput *_batcherInput;                      // Join up networked packets into one image.

    id <MediaDelayNotifier> _mediaDelayNotifier;       // Inform upstreams (e.g. GUI) of delay for debugging purposes.

    id <NewImageDelegate> _localImageDelegate;         // Display user's own camera to user (so that can see what other people see of them.

    // Does all the image compression/decompression and applying of filters.
    VideoCompression *_videoCompression;

    Signal *_isRunning;

    bool _loopbackEnabled;
    Timer *_fpsTracker;
    uint _fpsCount;

}
- (id)initWithUdpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDelayNotifier:(id <MediaDelayNotifier>)mediaDelayNotifier leftPadding:(uint)leftPadding loopbackEnabled:(bool)loopbackEnabled {
    self = [super init];
    if (self) {
        _loopbackEnabled = loopbackEnabled;
        _localImageDelegate = nil;

        if (_loopbackEnabled) {
            // Use the local image delegate, when that is loaded.
            newImageDelegate = nil;

            // Set later on in this constructor, null out now to avoid risk of using accidently.
            udpNetworkOutputSession = nil;
        }

        _videoCompression = [[VideoCompression alloc] init];
        _videoEncoder = [[VideoEncoding alloc] initWithVideoCompression:_videoCompression];

        _packetToImageProcessor = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate encoder:_videoEncoder];

        DelayedPipe *_syncWithAudio = [[DelayedPipe alloc] initWithMinimumDelay:0.1 outputSession:_packetToImageProcessor];

        _batcherInput = [[BatcherInput alloc] initWithOutputSession:_syncWithAudio timeoutMs:1000];
        [_batcherInput initialize];

        if (_loopbackEnabled) {
            // Handle the prefix which network would normally process at a higher level than this.
            DecodingPipe *loopbackDecodingPipe = [[DecodingPipe alloc] init];
            [loopbackDecodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_batcherInput];

            // Loop back around.
            udpNetworkOutputSession = loopbackDecodingPipe;
        }

        _encodingPipeVideo = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession prefixId:VIDEO_ID];

        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:_encodingPipeVideo leftPadding:leftPadding];

        _captureSession = [_videoEncoder setupCaptureSessionWithDelegate:self];

        _mediaDelayNotifier = mediaDelayNotifier;

        _isRunning = [[Signal alloc] initWithFlag:false];

        _fpsTracker = [[Timer alloc] initWithFrequencySeconds:1 firingInitially:false];
        _fpsCount = 0;
    }
    return self;
}

- (void)setOutputSession:(id <NewPacketDelegate>)newPacketDelegate {
    [_encodingPipeVideo setOutputSession:newPacketDelegate];
}

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate {
    _localImageDelegate = localImageDelegate;
    if (_loopbackEnabled) {
        [_packetToImageProcessor setNewImageDelegate:localImageDelegate];
    }
}

- (void)clearLocalImageDelegate {
    _localImageDelegate = nil;
}

- (void)startCapturing {
    @synchronized (self) {
        if ([_isRunning signalAll]) {
            NSLog(@"Starting video recording...");
            [_captureSession startRunning];
        }
    }
}

- (void)stopCapturing {
    @synchronized (self) {
        if ([_isRunning clear]) {
            NSLog(@"Stopped video recording...");
            [_captureSession stopRunning];
        }
    }
}

// Called when changing person we're talking to.
- (void)resetInbound {
    [_batcherInput reset];
    [_videoCompression resetFilters];
}

// Handle data from camera device and push out to network.
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (_localImageDelegate != nil && !_loopbackEnabled) {
        UIImage *localImage = [_videoEncoder convertSampleBufferToUiImage:sampleBuffer];
        if (localImage != nil) {
            [_localImageDelegate onNewImage:localImage];
            _fpsCount++;
        }
        if ([_fpsTracker getState]) {
            NSLog(@"Frame rate = %ufps", _fpsCount);
            _fpsCount = 0;
        }
    }

    // Send image as packet.
    ByteBuffer *rawBuffer = [[ByteBuffer alloc] init];

    if (![_videoEncoder addImage:sampleBuffer toByteBuffer:rawBuffer]) {
        return;
    }
    rawBuffer.cursorPosition = 0;

    [_batcherOutput onNewPacket:rawBuffer fromProtocol:UDP];
}

// Handle new data received on network to be pushed out to the user.
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    [_batcherInput onNewPacket:packet fromProtocol:protocol];
}

- (void)onMediaDataLossFromSender:(MediaType)mediaType {
    NSLog(@"Video data loss");
}


@end
