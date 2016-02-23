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
#import "EncodingPipe.h"
#import "DecodingPipe.h"
#import "DelayedPipe.h"
#import "AudioGraph.h"

@implementation MediaController {
    Boolean _started;

    // Video
    VideoOutputController *_videoOutputController;
    DelayedPipe *_delayedPipe;

    // Audio
    //SoundMicrophone *_soundEncoder;
    //SoundPlayback *_soundPlayback;
    EncodingPipe *_encodingPipeAudio;
    AudioGraph *_audioMicrophone;

    // Both audio and video.
    DecodingPipe *_decodingPipe;


}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDelayNotifier:(id <MediaDelayNotifier>)mediaDelayNotifier {
    self = [super init];
    if (self) {
        // A mode for testing where audio and video is looped round avoiding the network (so we see and hear ourselves immediately).
        const bool LOOPBACK_ENABLED = true;

        _started = false;

        Float64 secondsPerBuffer = 0.2; // estimate.
        Float64 estimatedDelay = 3 * secondsPerBuffer;

        const uint leftPadding = sizeof(uint8_t);

        _decodingPipe = [[DecodingPipe alloc] init];
        _delayedPipe = [[DelayedPipe alloc] initWithMinimumDelay:estimatedDelay outputSession:nil];


        // Video.
        _videoOutputController = [[VideoOutputController alloc] initWithUdpNetworkOutputSession:_delayedPipe imageDelegate:newImageDelegate mediaDelayNotifier:mediaDelayNotifier leftPadding:leftPadding loopbackEnabled:LOOPBACK_ENABLED];
        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];

        // Audio.
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:nil prefixId:AUDIO_ID];

        if (LOOPBACK_ENABLED) {
            // Signal to audio that it should loop back.
            _encodingPipeAudio = nil;
        }

        _audioMicrophone = [[AudioGraph alloc] initWithOutputSession:_encodingPipeAudio leftPadding:leftPadding];
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_audioMicrophone];
        [_audioMicrophone initialize];
    }
    return self;
}

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate {
    [_videoOutputController setLocalImageDelegate:localImageDelegate];
}

- (void)clearLocalImageDelegate {
    [_videoOutputController clearLocalImageDelegate];
}

- (void)start {
    @synchronized (self) {
        if (_started) {
            return;
        }
        _started = true;

        //NSLog(@"Starting video recording and microphone");
        //[_soundPlayback resetQueue];
        //[_soundEncoder startCapturing];
        //[_soundPlayback startPlayback];

        // We discard out of order batches based on keeping track of the batch ID.
        // We need to reset this when moving to the next person.
        [_videoOutputController resetInbound];
    }
}

- (void)stop {
    @synchronized (self) {
        if (!_started) {
            return;
        }
        _started = false;

        //NSLog(@"Stopping video recording and microphone");
        //[_soundEncoder stopCapturing];
        //[_soundPlayback stopPlayback];
    }
}

- (void)startVideo {
    // We use the video on the disconnect screen aswell, so once initialized, we never need to stop capturing.
    [_videoOutputController startCapturing];
}

- (void)stopVideo {
    // We use the video on the disconnect screen aswell, so once initialized, we never need to stop capturing.
    [_videoOutputController stopCapturing];
}

- (void)setNetworkOutputSessionUdp:(id <NewPacketDelegate>)udp {
    NSLog(@"Updating video output session UDP");
    [_encodingPipeAudio setOutputSession:udp];
    [_delayedPipe setOutputSession:udp];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (protocol == UDP) {
        packet.cursorPosition = 0;
        [_decodingPipe onNewPacket:packet fromProtocol:protocol];
    } else if (protocol == TCP) {
        NSLog(@"Invalid TCP packet received");
    }
}

- (void)resetSendRate {
    // This gets called when we move to another person, so discard any delayed video from previous person.
    [_delayedPipe reset];
}

@end
