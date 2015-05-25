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
#import "VideoOutputController.h"
#import "NetworkOperations.h"

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


@implementation MediaController {
    // Video
    VideoOutputController* _videoOutputController;
    
    // Audio
    SoundMicrophone* _soundEncoder;
    SoundPlayback* _soundPlayback;
    EncodingPipe* _encodingPipeAudio;
    OfflineAudioProcessor* _offlineAudioProcessor;
    
    // Both audio and video.
    DecodingPipe* _decodingPipe;
    
    id<NewPacketDelegate> _udpNetworkOutputSession;
    id<NewPacketDelegate> _tcpNetworkOutputSession;
    
    bool _connected;
}

- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate tcpNetworkOutputSession:(id<NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id<NewPacketDelegate>)udpNetworkOutputSession; {
    self = [super init];
    if(self) {
        _tcpNetworkOutputSession = tcpNetworkOutputSession;
        _udpNetworkOutputSession = udpNetworkOutputSession;
        
        _decodingPipe = [[DecodingPipe alloc] init];
        
        _videoOutputController = [[VideoOutputController alloc] initWithTcpNetworkOutputSession:_tcpNetworkOutputSession udpNetworkOutputSession:_udpNetworkOutputSession imageDelegate:newImageDelegate];

        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];
        
        
        // Audio.
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:_udpNetworkOutputSession andPrefixId:AUDIO_ID];
        
        
        Float64 secondsPerBuffer = 0.25;
        uint numBuffers = 3;
        
        _soundEncoder = [[SoundMicrophone alloc] initWithOutputSession:nil numBuffers:numBuffers leftPadding:sizeof(uint) secondPerBuffer:secondsPerBuffer];
        _soundPlayback = [[SoundPlayback alloc] initWithAudioDescription:[_soundEncoder getAudioDescription] secondsPerBuffer:secondsPerBuffer numBuffers:numBuffers restartPlaybackThreshold:3 maxPendingAmount:9];
        _offlineAudioProcessor = [[OfflineAudioProcessor alloc] initWithOutputSession:_soundPlayback];
        
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_soundPlayback];
        [_soundEncoder setOutputSession:_offlineAudioProcessor];
        
        NSLog(@"Initializing playback and recording...");
        [_soundEncoder start];
        [_soundPlayback start];
        
        _connected = false;
    }
    return self;
}


- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if(protocol == UDP) {
        packet.cursorPosition = 0;
        [_decodingPipe onNewPacket:packet fromProtocol:protocol];
    } else if(protocol == TCP) {
        uint prefix = [packet getUnsignedInteger];
        if(prefix == SLOW_DOWN_VIDEO) {
            NSLog(@"Slowing down video send rate");
            //[_throttledBlock slowRate];
        } else {
            NSLog(@"Invalid TCP packet received");
        }
    }
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
