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
#import "AudioGraph.h"
#import "SequenceEncodingPipe.h"

@implementation MediaController {
    Boolean _started;

    // Video
    VideoOutputController *_videoOutputController;

    // Audio
    EncodingPipe *_encodingPipeAudio;
    AudioGraph *_audioGraph;

    SequenceEncodingPipe *_audioSequenceEncodingPipe;
    SequenceDecodingPipe *_audioSequenceDecodingPipe;

    // Both audio and video.
    DecodingPipe *_decodingPipe;

    id <MediaDataLossNotifier> _mediaDelayNotifier;
    
    bool _loopbackEnabled;
}

- (id)initWithImageDelegate:(id <NewImageDelegate>)newImageDelegate mediaDataLossNotifier:(id <MediaDataLossNotifier>)mediaDataLossNotifier {
    self = [super init];
    if (self) {
        // A mode for testing where audio and video is looped round avoiding the network (so we see and hear ourselves immediately).
        _loopbackEnabled = false;

        _mediaDelayNotifier = mediaDataLossNotifier;
        _started = false;

        const uint leftPadding = sizeof(uint8_t);

        // Video.
        _videoOutputController = [[VideoOutputController alloc] initWithUdpNetworkOutputSession:nil imageDelegate:newImageDelegate mediaDataLossNotifier:mediaDataLossNotifier leftPadding:leftPadding loopbackEnabled:_loopbackEnabled];
        _decodingPipe = [[DecodingPipe alloc] init];
        [_decodingPipe addPrefix:VIDEO_ID mappingToOutputSession:_videoOutputController];

        // Audio.
        _audioSequenceEncodingPipe = [[SequenceEncodingPipe alloc] initWithOutputSession:nil];
        _encodingPipeAudio = [[EncodingPipe alloc] initWithOutputSession:_audioSequenceEncodingPipe prefixId:AUDIO_ID];

        if (_loopbackEnabled) {
            // Signal to audio that it should loop back.
            _encodingPipeAudio = nil;
        }

        _audioGraph = [[AudioGraph alloc] initWithOutputSession:_encodingPipeAudio leftPadding:leftPadding + sizeof(uint16_t) sequenceGapNotifier:self timeInQueueNotifier:self];
        _audioSequenceDecodingPipe = [[SequenceDecodingPipe alloc] initWithOutputSession:_audioGraph sequenceGapNotification:self];
        [_decodingPipe addPrefix:AUDIO_ID mappingToOutputSession:_audioSequenceDecodingPipe];
        [_audioGraph initialize];
        
        if (_loopbackEnabled) {
            [self startAudio];
            [self startVideo];
        }
    }
    return self;
}

- (void)setLocalImageDelegate:(id <NewImageDelegate>)localImageDelegate {
    [_videoOutputController setLocalImageDelegate:localImageDelegate];
}

- (void)clearLocalImageDelegate {
    [_videoOutputController clearLocalImageDelegate];
}

- (void)startAudio {
    @synchronized (self) {
        if (_started) {
            return;
        }
        _started = true;

        NSLog(@"Starting video recording and microphone");
        [_audioGraph start];
    }
}

- (void)stopAudio {
    if (_loopbackEnabled) {
        return;
    }
    
    @synchronized (self) {
        if (!_started) {
            return;
        }
        _started = false;

        // Don't stop the video because we use that in disconnect screen too.
        NSLog(@"Stopping microphone and speaker");
        [_audioGraph stop];
    }
}

- (void)startVideo {
    // We discard out of order batches based on keeping track of the batch ID.
    // We need to reset this when moving to the next person.
    [_videoOutputController resetInbound];

    // We use the video on the disconnect screen aswell, so once initialized, we never need to stop capturing.
    [_videoOutputController startCapturing];
}

- (void)stopVideo {
    if (_loopbackEnabled) {
        return;
    }
    
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

- (bool)isAudioPacket:(ByteBuffer*)buffer {
    uint operationId = [buffer getUnsignedIntegerAtPosition8:0];
    return operationId == AUDIO_ID;
}

- (void)resetSendRate {
    // This gets called when we move to another person, so discard any delayed video from previous person.
}

- (void)onSequenceGap:(uint)gapSize fromSender:(id)sender {
    if (sender == _audioSequenceDecodingPipe) {
        NSLog(@"Gap size of %u for audio", gapSize);
        [_mediaDelayNotifier onMediaDataLossFromSender:AUDIO];
    } else if (sender == _audioGraph) {
        NSLog(@"Audio reset detected of approximately %d items", gapSize);
        [_mediaDelayNotifier onMediaDataLossFromSender:AUDIO_QUEUE_RESET];
    } else {
        NSLog(@"Unknown media data loss sender");
    }
}

// Receive notification from audio on how much delay there is.
- (void)onTimeInQueueNotification:(uint)timeInQueueMs {
    [_videoOutputController setVideoDelayMs:timeInQueueMs];
}


@end
