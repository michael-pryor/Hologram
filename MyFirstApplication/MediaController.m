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
#import "SequenceEncodingPipe.h"
#import "SequenceDecodingPipe.h"

@implementation MediaController {
    Boolean _started;

    // Video
    VideoOutputController *_videoOutputController;

    // Audio
    EncodingPipe *_encodingPipeAudio;
    AudioGraph *_audioMicrophone;

    SequenceEncodingPipe * _audioSequenceEncodingPipe;
    SequenceDecodingPipe * _audioSequenceDecodingPipe;

    // Both audio and video.
    DecodingPipe *_decodingPipe;

    id <MediaDelayNotifier> _mediaDelayNotifier;
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDelayNotifier:(id <MediaDelayNotifier>)mediaDelayNotifier {
    self = [super init];
    if (self) {
        // A mode for testing where audio and video is looped round avoiding the network (so we see and hear ourselves immediately).
        const bool LOOPBACK_ENABLED = false;

        _mediaDelayNotifier = mediaDelayNotifier;
        _started = false;

        const uint leftPadding = sizeof(uint8_t);

        // Video.
        _videoOutputController = [[VideoOutputController alloc] initWithUdpNetworkOutputSession:nil imageDelegate:newImageDelegate mediaDelayNotifier:mediaDelayNotifier leftPadding:leftPadding loopbackEnabled:LOOPBACK_ENABLED];
        _decodingPipe = [[DecodingPipe alloc] init];
        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];

        // Audio.
        _audioSequenceEncodingPipe = [[SequenceEncodingPipe alloc] initWithOutputSession:nil];
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:_audioSequenceEncodingPipe prefixId:AUDIO_ID];

        if (LOOPBACK_ENABLED) {
            // Signal to audio that it should loop back.
            _encodingPipeAudio = nil;
        }

        _audioMicrophone = [[AudioGraph alloc] initWithOutputSession:_encodingPipeAudio leftPadding:leftPadding+ sizeof(uint16_t)];
        _audioSequenceDecodingPipe = [[SequenceDecodingPipe alloc] initWithOutputSession:_audioMicrophone sequenceGapNotification:self];
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_audioSequenceDecodingPipe];
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

        NSLog(@"Starting video recording and microphone");
        [_audioMicrophone start];

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

        // Don't stop the video because we use that in disconnect screen too.
        NSLog(@"Stopping microphone and speaker");
        [_audioMicrophone stop];
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
    [_audioSequenceEncodingPipe setOutputSession:udp];
    [_videoOutputController setOutputSession:udp];
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
}

- (void)onSequenceGap:(uint)gapSize fromSender:(id)sender {
    if (sender == _audioSequenceDecodingPipe) {
        NSLog(@"Gap size of %u for audio", gapSize);
        [_mediaDelayNotifier onMediaDataLossFromSender:AUDIO];
    } else {
        NSLog(@"Gap size of %u for video", gapSize);
        [_mediaDelayNotifier onMediaDataLossFromSender:VIDEO];
    }
}


@end
