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

@implementation MediaController {
    Boolean _started;

    // Video
    VideoOutputController *_videoOutputController;
    DelayedPipe *_delayedPipe;

    // Audio
    SoundMicrophone *_soundEncoder;
    SoundPlayback *_soundPlayback;
    EncodingPipe *_encodingPipeAudio;
    EncodingPipe *_encodingPipeAudioVideoSync;
    TimedEventTracker *_startStopTracker;

    // Both audio and video.
    DecodingPipe *_decodingPipe;
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate videoSpeedNotifier:(id <VideoSpeedNotifier>)videoSpeedNotifier tcpNetworkOutputSession:(id <NewPacketDelegate>)tcpNetworkOutputSession udpNetworkOutputSession:(id <NewPacketDelegate>)udpNetworkOutputSession mediaDelayNotifier:(id <MediaDelayNotifier>)mediaDelayNotifier {
    self = [super init];
    if (self) {
        _started = false;
        _startStopTracker = [[TimedEventTracker alloc] initWithMaxEvents:8 timePeriod:5];

        // Buffering estimations (introduce delay so that playback is smooth).
        uint numMicrophoneBuffers = 10;
        uint numPlaybackAudioBuffers = 2;
        uint maxPlaybackPendingBuffers = 50;

        Float64 secondsPerBuffer = 0.2; // estimate.
        Float64 estimatedDelay = 3 * secondsPerBuffer;

        _decodingPipe = [[DecodingPipe alloc] init];
        _delayedPipe = [[DelayedPipe alloc] initWithMinimumDelay:estimatedDelay outputSession:udpNetworkOutputSession];

        // Video.
        _videoOutputController = [[VideoOutputController alloc] initWithTcpNetworkOutputSession:tcpNetworkOutputSession udpNetworkOutputSession:_delayedPipe imageDelegate:newImageDelegate videoSpeedNotifier:videoSpeedNotifier mediaDelayNotifier:mediaDelayNotifier];

        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];


        // Audio.
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:udpNetworkOutputSession prefixId:AUDIO_ID];


        _soundEncoder = [[SoundMicrophone alloc] initWithOutputSession:nil numBuffers:numMicrophoneBuffers leftPadding:sizeof(uint8_t)];
        [_soundEncoder initialize];

        _soundPlayback = [[SoundPlayback alloc] initWithAudioDescription:[_soundEncoder getAudioDescription] numBuffers:numPlaybackAudioBuffers maxPendingAmount:maxPlaybackPendingBuffers soundPlaybackDelegate:self mediaDelayDelegate:_videoOutputController];
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
    @synchronized (self) {
        if (_started) {
            return;
        }
        _started = true;

        NSLog(@"Starting video recording and microphone");
        [_soundPlayback resetQueue];
        [_videoOutputController start];
        [_soundEncoder startCapturing];
        [_soundPlayback startPlayback];
    }
}

- (void)stop {
    @synchronized (self) {
        if (!_started) {
            return;
        }
        _started = false;

        NSLog(@"Stopping video recording and microphone");
        [_videoOutputController stop];
        [_soundEncoder stopCapturing];
        [_soundPlayback stopPlayback];
    }
}

- (void)setNetworkOutputSessionTcp:(id <NewPacketDelegate>)tcp Udp:(id <NewPacketDelegate>)udp {
    [_encodingPipeAudio setOutputSession:udp];
    NSLog(@"Updating video output session UDP");
    [_delayedPipe setOutputSession:udp];
    [_videoOutputController setNetworkOutputSessionTcp:tcp];
    [_videoOutputController resetSendRate];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (protocol == UDP) {
        packet.cursorPosition = 0;
        [_decodingPipe onNewPacket:packet fromProtocol:protocol];
    } else if (protocol == TCP) {
        uint prefix = [packet getUnsignedInteger8];
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
