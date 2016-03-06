//
// Created by Michael Pryor on 06/03/2016.
//

#import <Foundation/Foundation.h>
@import AVFoundation;

struct AudioFormatProcessResult {
    uint framesPerBuffer;
    uint bytesPerBuffer;
};
typedef struct AudioFormatProcessResult  AudioFormatProcessResult;

@interface AudioSessionInteractions : NSObject
@property(readonly) double hardwareSampleRate;
@property(readonly) double hardwareBufferDuration;

+ (id)instance;

- (void)setupAudioSessionWithDesiredHardwareSampleRate:(double)sampleRate desiredBufferDuration:(double)ioBufferDuration;

- (struct AudioFormatProcessResult)processAudioFormat:(AudioStreamBasicDescription)description bufferDuration:(double)bufferDuration;

- (struct AudioFormatProcessResult)processAudioFormat:(AudioStreamBasicDescription)description;
@end