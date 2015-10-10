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
#import "SoundMicrophone.h"
#import "EncodingPipe.h"
#import "DecodingPipe.h"
#import "TimedEventTracker.h"

@implementation OfflineAudioProcessor : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession {
    self = [super initWithOutputSession:outputSession];
    if (self) {

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
    Boolean _started;

    // Video
    VideoOutputController *_videoOutputController;

    // Audio
    SoundMicrophone *_soundEncoder;
    SoundPlayback *_soundPlayback;
    EncodingPipe *_encodingPipeAudio;
    OfflineAudioProcessor *_offlineAudioProcessor;
    TimedEventTracker *_startStopTracker;

    // Both audio and video.
    DecodingPipe *_decodingPipe;
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier tcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession; {
    self = [super init];
    if (self) {
        _started = false;
        _startStopTracker = [[TimedEventTracker alloc] initWithMaxEvents:8 timePeriod:5];


        _decodingPipe = [[DecodingPipe alloc] init];

        _videoOutputController = [[VideoOutputController alloc] initWithTcpNetworkOutputSession:tcpNetworkOutputSession udpNetworkOutputSession:udpNetworkOutputSession imageDelegate:newImageDelegate videoSpeedNotifier:videoSpeedNotifier];

        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];


        // Audio.
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession andPrefixId:AUDIO_ID];


        Float64 secondsPerBuffer = 0.1;
        uint numBuffers = 6;

        _soundEncoder = [[SoundMicrophone alloc] initWithOutputSession:nil numBuffers:numBuffers leftPadding:sizeof(uint) secondPerBuffer:secondsPerBuffer];
        _soundPlayback = [[SoundPlayback alloc] initWithAudioDescription:[_soundEncoder getAudioDescription] secondsPerBuffer:secondsPerBuffer numBuffers:numBuffers restartPlaybackThreshold:6 maxPendingAmount:30 soundPlaybackDelegate:self];
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_soundPlayback];
        [_soundEncoder setOutputSession:_encodingPipeAudio];

        [_soundEncoder initialize];
        [_soundPlayback initialize];
        NSLog(@"Audio recording and playback initialized");
    }
    return self;
}

- (void)start {
    if (_started) {
        return;
    }
    _started = true;

    NSLog(@"Starting video recording");
    [_videoOutputController start];

    NSLog(@"Starting audio playback and recording...");
    [_soundEncoder startCapturing];
}

- (void)stop {
    if (!_started) {
        return;
    }
    _started = false;

    NSLog(@"Stopping video recording");
    [_videoOutputController stop];

    NSLog(@"Starting audio playback and recording...");
    [_soundEncoder stopCapturing];
}

- (void)setNetworkOutputSessionTcp:(id <NewPacketDelegate>)tcp Udp:(id <NewPacketDelegate>)udp {
    [_encodingPipeAudio setOutputSession:udp];
    [_videoOutputController setNetworkOutputSessionTcp:tcp Udp:udp];
    [_videoOutputController resetSendRate];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (protocol == UDP) {
        packet.cursorPosition = 0;
        [_decodingPipe onNewPacket:packet fromProtocol:protocol];
    } else if (protocol == TCP) {
        uint prefix = [packet getUnsignedInteger];
        if (prefix == SLOW_DOWN_VIDEO) {
            NSLog(@"Slowing down video send rate");
            [_videoOutputController slowSendRate];
        } else if (prefix == RESET_VIDEO_SPEED) {
            NSLog(@"Video speed reset");
            [_videoOutputController resetSendRate];
        } else {
            NSLog(@"Invalid TCP packet received");
        }
    }
}

- (void)resetSendRate {
    [_videoOutputController resetSendRate];
}

- (void)sendSlowdownRequest {
    [_videoOutputController sendSlowdownRequest];
}

- (void)playbackStopped {
    if ([_startStopTracker increment]) {
        NSLog(@"Playback start/stopped too many times in a short space of time, slowing video send rate to free up network");
        [self sendSlowdownRequest];
    }
}

- (void)playbackStarted {
    if ([_startStopTracker increment]) {
        NSLog(@"Playback start/stopped too many times in a short space of time, slowing video send rate to free up network");
        [self sendSlowdownRequest];
    }
}
@end
