//
//  MediaController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 07/01/2015.
//
//

#import "VideoEncoding.h"
#import "OutputSessionTcp.h"
#import "MediaController.h"
#import "BatcherInput.h"
#import "BatcherOutput.h"
#import "SoundMicrophone.h"
#import "SoundPlayback.h"
#import "EncodingPipe.h"
#import "DecodingPipe.h"

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
    [_newImageDelegate onNewImage: image];
}
@end

@implementation OfflineAudioProcessor : PipelineProcessor
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession {
    self = [super initWithOutputSession: outputSession];
    if(self) {
        
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    // Skip the left padding, since we don't need this when not using networking.
    [packet setCursorPosition:sizeof(uint)];
    [_outputSession onNewPacket:packet fromProtocol:protocol];
}
@end


#define AUDIO_ID 1
#define VIDEO_ID 2
@implementation MediaController {
    // Video
    AVCaptureSession* _session;
    id<NewImageDelegate> _newImageDelegate;
    VideoEncoding* _mediaEncoder;
    BatcherInput* _batcherInput;
    BatcherOutput* _batcherOutput;
    
    EncodingPipe* _encodingPipeVideo;
    
    // Audio
    SoundMicrophone* _soundEncoder;
    SoundPlayback* _soundPlayback;
    
    EncodingPipe* _encodingPipeAudio;
    
    OfflineAudioProcessor* _offlineAudioProcessor;
    
    // Both audio and video.
    DecodingPipe* _decodingPipe;
    
    id<NewPacketDelegate> _networkOutputSession;
    
    
    
    bool _connected;
}

- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate andwithNetworkOutputSession:(id<NewPacketDelegate>)networkOutputSession {
    self = [super init];
    if(self) {
        _networkOutputSession = networkOutputSession;
        
        _decodingPipe = [[DecodingPipe alloc] init];
        
        // Setup video input/output.
        // Video frames from this device are sent to a callback in this class.
	    _newImageDelegate = newImageDelegate;

        _mediaEncoder = [[VideoEncoding alloc] init];
        _session = [_mediaEncoder setupCaptureSessionWithDelegate: self];

        PacketToImageProcessor * p = [[PacketToImageProcessor alloc] initWithImageDelegate:newImageDelegate encoder:_mediaEncoder];
        
        _encodingPipeVideo = [[EncodingPipe alloc] initWithOutputSession:networkOutputSession andPrefixId:VIDEO_ID];
        
        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:_encodingPipeVideo andChunkSize:[_mediaEncoder suggestedBatchSize] withLeftPadding:sizeof(uint) includeTotalChunks:true];
        _batcherInput = [[BatcherInput alloc] initWithOutputSession:p chunkSize:[_mediaEncoder suggestedBatchSize] numChunks:0 andNumChunksThreshold:1.0 andTimeoutMs:100];

        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_batcherInput];
        
        
        // Audio.
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:networkOutputSession andPrefixId:AUDIO_ID];
        
        
        Float64 secondsPerBuffer = 0.25;
        uint numBuffers = 3;
        
        _soundEncoder = [[SoundMicrophone alloc] initWithOutputSession:nil numBuffers:numBuffers leftPadding:sizeof(uint) secondPerBuffer:secondsPerBuffer];
        _soundPlayback = [[SoundPlayback alloc] initWithAudioDescription:[_soundEncoder getAudioDescription] secondsPerBuffer:secondsPerBuffer numBuffers:numBuffers restartPlaybackThreshold:2 maxPendingAmount:2];
        _offlineAudioProcessor = [[OfflineAudioProcessor alloc] initWithOutputSession:_soundPlayback];
        
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_soundPlayback];
        [_soundEncoder setOutputSession:_offlineAudioProcessor];
        
        NSLog(@"Initializing playback and recording...");
        [_soundEncoder start];
        [_soundPlayback start];
        
        NSLog(@"Starting recording...");
        [_soundEncoder startCapturing];
        
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
        
        [_mediaEncoder addImage:sampleBuffer toByteBuffer:rawBuffer];
        rawBuffer.cursorPosition = 0;

        [_batcherOutput onNewPacket:rawBuffer fromProtocol:UDP];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    packet.cursorPosition = 0;
    [_decodingPipe onNewPacket:packet fromProtocol:protocol];
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    _connected = status == P_CONNECTED;
    
    if(!_connected) {
        [_soundEncoder setOutputSession:_offlineAudioProcessor];
    } else {
        [_soundEncoder setOutputSession:_encodingPipeAudio];
    }
}

@end
