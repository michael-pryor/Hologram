//
//  MediaController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 07/01/2015.
//
//

#import "MediaByteBuffer.h"
#import "Encoding.h"
#import "OutputSessionTcp.h"
#import "MediaController.h"
#import "BatcherInput.h"
#import "BatcherOutput.h"
#import "SoundEncoding.h"
#import "SoundPlayback.h"

@implementation PacketToImageProcessor {
    id<NewImageDelegate> _newImageDelegate;
}
- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate {
    self = [super init];
    if(self) {
	    _newImageDelegate = newImageDelegate;
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    // Update display with image retrieved from packet.
    MediaByteBuffer* buffer = [[MediaByteBuffer alloc] initFromBuffer: packet];
    UIImage *image = [buffer getImage];
    [_newImageDelegate onNewImage: image];
}
@end

@implementation MediaController {
    AVCaptureSession* _session;
    id<NewImageDelegate> _newImageDelegate;
    Encoding* _mediaEncoder;
    BatcherInput* _batcherInput;
    BatcherOutput* _batcherOutput;
    
    // Audio
    SoundEncoding* _soundEncoder;
    SoundPlayback* _soundPlayback;
    
    
    bool _connected;
}

- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate andwithNetworkOutputSession:(id<NewPacketDelegate>)networkOutputSession {
    self = [super init];
    if(self) {
	    _newImageDelegate = newImageDelegate;

        _mediaEncoder = [[Encoding alloc] init];
        _session = [_mediaEncoder setupCaptureSessionWithDelegate: self];

        PacketToImageProcessor * p = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate];
        
        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:networkOutputSession andChunkSize:[_mediaEncoder suggestedBatchSize]];
        _batcherInput = [[BatcherInput alloc] initWithOutputSession:p chunkSize:[_mediaEncoder suggestedBatchSize] numChunks:[_mediaEncoder suggestedBatches] andNumChunksThreshold:[_mediaEncoder suggestedBatches] andTimeoutMs:100];
        
        _soundEncoder = [[SoundEncoding alloc] init];
        _soundPlayback = [[SoundPlayback alloc] initWithAudioDescription:[_soundEncoder getAudioDescription]];
        [_soundEncoder setOutputSession:_soundPlayback];
        
        NSLog(@"Initializing playback and recording...");
        [_soundEncoder start];
        [_soundPlayback start];
        
        NSLog(@"Starting recording...");
        [_soundEncoder startCapturing];
        
        NSLog(@"Starting playback...");
        [_soundPlayback startPlayback];
        
        _connected = false;
    }
    return self;
}

- (void) startCapturing {
    [_session startRunning];
    //[_soundEncoder startCapturing];
    //[_soundPlayback startPlayback];
}

- (void) stopCapturing {
    [_session stopRunning];
    [_soundEncoder stopCapturing];
    //[_soundPlayback stopPlayback];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if(!_connected) {
        // update display with no networking.
        UIImage *image = [_mediaEncoder imageFromSampleBuffer: sampleBuffer];
        [_newImageDelegate onNewImage: image];
    } else {
        // Send image as packet.
        ByteBuffer * rawBuffer = [[ByteBuffer alloc] init];
        MediaByteBuffer* buffer = [[MediaByteBuffer alloc] initFromBuffer: rawBuffer];
        [buffer addImage: sampleBuffer];
        rawBuffer.cursorPosition = 0;
        [_batcherOutput onNewPacket:rawBuffer fromProtocol:UDP];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    packet.cursorPosition = 0;
    [_batcherInput onNewPacket:packet fromProtocol:protocol];
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    _connected = status == P_CONNECTED;
}

@end
