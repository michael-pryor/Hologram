//
// Created by Michael Pryor on 06/03/2016.
//

#import "AudioSessionInteractions.h"

@implementation AudioSessionInteractions {
}

+ (id)instance {
    static AudioSessionInteractions *sharedAudioSessionInteractions = nil;
    @synchronized (self) {
        if (sharedAudioSessionInteractions == nil) {
            sharedAudioSessionInteractions = [[self alloc] init];
        }
    }
    return sharedAudioSessionInteractions;
}

- (void)setupAudioSessionWithDesiredHardwareSampleRate:(double)sampleRate desiredBufferDuration:(double)ioBufferDuration {
    NSError *audioSessionError = nil;
    AVAudioSession *mySession = [AVAudioSession sharedInstance];
    BOOL result = [mySession setPreferredSampleRate:sampleRate
                                              error:&audioSessionError];
    if (!result) {
        NSLog(@"Preferred sample rate of %.2f not allowed, reason: %@", sampleRate, [audioSessionError localizedFailureReason]);
    }

    // Use the device's loud speaker if no headphones are plugged in.
    // Without this, will use the quiet speaker if available, e.g. on iphone this is for taking calls privately.
    NSError *error;
    result = [mySession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    if (!result) {
        NSLog(@"Failed to enable AVAudioSessionCategoryOptionDefaultToSpeaker mode: %@", [error localizedDescription]);
    }

    result = [mySession setMode:AVAudioSessionModeVideoChat error:&error];
    if (!result) {
        NSLog(@"Failed to enable AVAudioSessionModeVideoChat mode, reason: %@", [error localizedDescription]);
    }

    // Lower latency.
    result = [mySession setPreferredIOBufferDuration:ioBufferDuration
                                               error:&audioSessionError];
    if (!result) {
        NSLog(@"Failed to set buffer duration to %.5f, reason: %@", ioBufferDuration, [audioSessionError localizedFailureReason]);
    }

    result = [mySession setActive:YES
                            error:&audioSessionError];
    if (!result) {
        NSLog(@"Failed to activate audio session, reason: %@", [audioSessionError localizedFailureReason]);
    }

    _hardwareSampleRate = [mySession sampleRate];
    NSLog(@"Device sample rate is: %.2f", _hardwareSampleRate);

    _hardwareBufferDuration = [mySession IOBufferDuration];
    NSLog(@"Buffer duration: %.2f", _hardwareBufferDuration);
}

- (struct AudioFormatProcessResult)processAudioFormat:(AudioStreamBasicDescription)description {
    return [self processAudioFormat:description bufferDuration:_hardwareBufferDuration];
}

- (struct AudioFormatProcessResult)processAudioFormat:(AudioStreamBasicDescription)description bufferDuration:(double)bufferDuration {
    struct AudioFormatProcessResult result;
    result.framesPerBuffer = (uint)ceil(description.mSampleRate * bufferDuration);
    result.bytesPerBuffer = (uint)ceil(result.framesPerBuffer * description.mBytesPerFrame);
    return result;
}
@end