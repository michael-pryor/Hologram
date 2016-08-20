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
#import "Threading.h"
#import "MemoryAwareObjectContainer.h"


#define ENCODING_FRAME_RATE 15

#define LOCAL_FRAME_RATE 15

@implementation PacketToImageProcessor {
    __weak id <NewImageDelegate> _newImageDelegate;
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

- (void)dealloc {
    NSLog(@"PacketToImageProcessor dealloc");
}
@end


@implementation VideoOutputController {
    AVCaptureSession *_captureSession;                 // Link to video input hardware.
    BatcherOutput *_batcherOutput;                     // Split up image into multiple packets for network.
    VideoEncoding *_videoEncoder;                      // Convert between network and image formats.
    EncodingPipe *_encodingPipeVideo;                  // Add appropriate prefix for transport over network.
    PacketToImageProcessor *_packetToImageProcessor;   // Convert compressed network packets into UIImage objects.

    BatcherInput *_batcherInput;                       // Join up networked packets into one image.

    DelayedPipe *_syncWithAudio;

    SequenceDecodingPipe *_dataLossDetector;          // Inspects the batch ID (without moving the cursor),
    // in order to detect data loss i.e. missing batches.

    id <MediaDataLossNotifier> _mediaDataLossNotifier; // Inform upstreams (e.g. GUI) of media data loss for debugging purposes.

    id <NewImageDelegate> _localImageDelegate;         // Display user's own camera to user (so that can see what other people see of them.

    // Does all the image compression/decompression and applying of filters.
    MemoryAwareObjectContainer *_videoCompression;

    Signal *_isRunning;

    bool _loopbackEnabled;
    Timer *_fpsTracker;
    uint _fpsCount;
}
- (id)initWithUdpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession imageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDataLossNotifier:(id <MediaDataLossNotifier>)mediaDataLossNotifier leftPadding:(uint)leftPadding loopbackEnabled:(bool)loopbackEnabled {
    self = [super init];
    if (self) {
        _loopbackEnabled = loopbackEnabled;
        _localImageDelegate = nil;

        if (_loopbackEnabled) {
            // Set later on in this constructor, null out now to avoid risk of using accidently.
            udpNetworkOutputSession = nil;
        }

        _videoCompression = [[MemoryAwareObjectContainer alloc] initWithConstructorBlock:^{
            return [[VideoCompression alloc] init];
        }];

        _videoEncoder = [[VideoEncoding alloc] initWithVideoCompression:_videoCompression];

        _packetToImageProcessor = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate encoder:_videoEncoder];

        _syncWithAudio = [[DelayedPipe alloc] initWithMinimumDelay:0.1 outputSession:_packetToImageProcessor];

        _batcherInput = [[BatcherInput alloc] initWithOutputSession:_syncWithAudio timeoutMs:1000];

        _dataLossDetector = [[SequenceDecodingPipe alloc] initWithOutputSession:_batcherInput sequenceGapNotification:self shouldMoveCursor:false];
        [_batcherInput initialize];

        if (_loopbackEnabled) {
            // Handle the prefix which network would normally process at a higher level than this.
            DecodingPipe *loopbackDecodingPipe = [[DecodingPipe alloc] init];
            [loopbackDecodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_batcherInput];

            // Loop back around.
            udpNetworkOutputSession = loopbackDecodingPipe;
        }

        _encodingPipeVideo = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession prefixId:VIDEO_ID position:0];

        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:_encodingPipeVideo leftPadding:leftPadding];


        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(captureSessionDidStopRunning:)
                                                     name:AVCaptureSessionDidStopRunningNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(captureSessionError:)
                                                     name:AVCaptureSessionRuntimeErrorNotification
                                                   object:nil];

        [self prepareVideoCaptureSession];

        _mediaDataLossNotifier = mediaDataLossNotifier;

        _isRunning = [[Signal alloc] initWithFlag:false];

        _fpsTracker = [[Timer alloc] initWithFrequencySeconds:1 firingInitially:false];
        _fpsCount = 0;

    }
    return self;
}

- (void)setVideoDelayMs:(uint)videoDelay {
    NSLog(@"Video delay set to %dms", videoDelay);
    [_syncWithAudio setMinimumDelay:((float)videoDelay) / 1000.0];
}

- (void)prepareVideoCaptureSession {
    @synchronized (self) {
        _captureSession = [_videoEncoder setupCaptureSessionWithDelegate:self];

        // We have seen failures to prepare the video capture session, this is a fail safe to keep retrying,
        // because we need it in order to be operational.
        __weak VideoOutputController *weakSelf = self;
        if (_captureSession == nil) {
            dispatch_async_main(^{
                [weakSelf prepareVideoCaptureSession];
            }, 1000);
        }
    }
}

- (void)setOutputSession:(id <NewPacketDelegate>)newPacketDelegate {
    if (_loopbackEnabled) {
        return;
    }

    [_encodingPipeVideo setOutputSession:newPacketDelegate];
}

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate {
    _localImageDelegate = localImageDelegate;
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

- (bool)stopCapturing {
    @synchronized (self) {
        if ([_isRunning clear]) {
            NSLog(@"Stopped video recording...");
            [_captureSession stopRunning];
            return true;
        }
        return false;
    }
}

- (void)captureSessionDidStopRunning:(NSNotification *)notification {
    @synchronized (self) {
        if([_isRunning clear]) {
            NSLog(@"Video capture session stopped, flag is out of sync, corrected");
            // Don't attempt to restart here because if in background will infinitely loop as OS stops us.
        }
    }
}

- (void)attemptStart {
    @synchronized (self) {
        __weak VideoOutputController *weakSelf = self;
        if (_captureSession != nil) {
            dispatch_async_main(^{
                [weakSelf startCapturing];
            }, 1000);
        }
    }
}

- (void)captureSessionError:(NSNotification *)notification {
    @synchronized (self) {
        NSError *error = [notification userInfo][AVCaptureSessionErrorKey];
        NSString *description;
        if (error != nil) {
            description = [error localizedDescription];
        } else {
            description = @"[unknown]";
        }

        NSLog(@"Video capture session failed with error: [%@], attempting to start again", description);

        [_isRunning clear];
        [self attemptStart];
    }
}

// Called when changing person we're talking to.
- (void)resetInbound {
    [_batcherInput reset];
    [[_videoCompression get] resetFilters];
    [_syncWithAudio reset];
}

// Handle data from camera device and push out to network.
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (_localImageDelegate != nil) {
        [_videoEncoder setFrameRate:LOCAL_FRAME_RATE];
        UIImage *localImage = [_videoEncoder convertSampleBufferToUiImage:sampleBuffer];
        if (localImage != nil) {
            // Make a copy, incase reference count goes to 0 mid way through operation.
            id <NewImageDelegate> delegate = _localImageDelegate;
            [delegate onNewImage:localImage];
        }

        if (_loopbackEnabled) {
            return;
        }
    } else {
        [_videoEncoder setFrameRate:ENCODING_FRAME_RATE];
    }

    _fpsCount++;
    if ([_fpsTracker getState]) {
        NSLog(@"Frame rate = %ufps", _fpsCount);
        _fpsCount = 0;
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
    [_dataLossDetector onNewPacket:packet fromProtocol:protocol];
}

- (void)onSequenceGap:(uint)gapSize fromSender:(id)sender {
    NSLog(@"Video data loss detected with gap size: %u", gapSize);
    [_mediaDataLossNotifier onMediaDataLossFromSender:VIDEO];
}

- (void)dealloc {
     NSLog(@"VideoOutputController dealloc");
    [self stopCapturing];

    // Need to terminate the thread.
    [_batcherInput terminate];
}

- (void)reduceMemoryUsage {
    [_videoCompression reduceMemoryUsage];
}
@end
