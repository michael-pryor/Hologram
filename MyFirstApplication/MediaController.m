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
#import "DelayedPipe.h"

@implementation OfflineAudioProcessor : PipelineProcessor
//Add a comment to this line
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession {
    self = [super initWithOutputSession:outputSession];
    if (self) {

    }
    return self;
}

- (void)
onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    // Skip the left padding, since we don't need this when not using networking.
    [packet setCursorPosition:sizeof(uint)];
    [_outputSession onNewPacket:packet fromProtocol:protocol];
}
@end

@implementation MediaController {
    Boolean _started;

    // Video
    VideoOutputController *_videoOutputController;
    DelayedPipe *_delayedPipe;

    // Audio
    SoundMicrophone *_soundEncoder;
    SoundPlayback *_soundPlayback;
    EncodingPipe *_encodingPipeAudio;
    TimedEventTracker *_startStopTracker;

    // Both audio and video.
    DecodingPipe *_decodingPipe;
}

- (void)echoBackForTesting {
    OfflineAudioProcessor * offlineAudioProcessor = [[OfflineAudioProcessor alloc] initWithOutputSession:_soundPlayback];
    [_soundEncoder setOutputSession:offlineAudioProcessor];
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier tcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession; {
    self = [super init];
    if (self) {
        _started = false;
        _startStopTracker = [[TimedEventTracker alloc] initWithMaxEvents:8 timePeriod:5];

        // Buffering estimations (introduce delay so that playback is smooth).
        Float64 secondsPerBuffer = 0.1;
        uint numBuffers = 3;

        Float64 estimatedDelay = numBuffers * secondsPerBuffer * 2;

        _decodingPipe = [[DecodingPipe alloc] init];
        _delayedPipe = [[DelayedPipe alloc] initWithMinimumDelay:estimatedDelay outputSession:udpNetworkOutputSession];

        // Video.
        _videoOutputController = [[VideoOutputController alloc] initWithTcpNetworkOutputSession:tcpNetworkOutputSession udpNetworkOutputSession:_delayedPipe imageDelegate:newImageDelegate videoSpeedNotifier:videoSpeedNotifier];

        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];


        // Audio.
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession andPrefixId:AUDIO_ID];

        _soundEncoder = [[SoundMicrophone alloc] initWithOutputSession:nil numBuffers:numBuffers leftPadding:sizeof(uint) secondPerBuffer:secondsPerBuffer];
        [_soundEncoder initialize];

        _soundPlayback = [[SoundPlayback alloc] initWithAudioDescription:[_soundEncoder getAudioDescription] secondsPerBuffer:secondsPerBuffer numBuffers:numBuffers restartPlaybackThreshold:3 maxPendingAmount:30 soundPlaybackDelegate:self];
        [_soundPlayback setMagicCookie:[_soundEncoder getMagicCookie] size:[_soundEncoder getMagicCookieSize]];
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_soundPlayback];

        [_soundEncoder setOutputSession:_encodingPipeAudio];
       // [self echoBackForTesting];

        [_soundPlayback initialize];
        NSLog(@"Audio microphone and speaker initialized");
    }
    return self;
}

- (void)start {
    if (_started) {
        return;
    }
    _started = true;

    NSLog(@"Starting video recording and microphone");
    [_videoOutputController start];
    [_soundEncoder startCapturing];
    [_soundPlayback startPlayback];
}

- (void)stop {
    if (!_started) {
        return;
    }
    _started = false;

    NSLog(@"Stopping video recording and microphone");
    [_videoOutputController stop];
    [_soundEncoder stopCapturing];
    [_soundPlayback stopPlayback];
}

- (void)setNetworkOutputSessionTcp:(id <NewPacketDelegate>)tcp Udp:(id <NewPacketDelegate>)udp {
    [_encodingPipeAudio setOutputSession:udp];
    NSLog(@"Updating video output session UDP");
    [_delayedPipe setOutputSession: udp];
    [_videoOutputController setNetworkOutputSessionTcp:tcp];
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

    // This gets called when we move to another person, so discard any delayed video from previous person.
    [_delayedPipe reset];
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
