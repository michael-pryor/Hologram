//
// Created by Michael Pryor on 05/03/2016.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;
#import "AudioShared.h"

@interface AudioPcmConversion : NSObject
- (id)initWithInputFormat:(AudioStreamBasicDescription *)inputFormat outputFormat:(AudioStreamBasicDescription *)outputFormat outputResult:(id <AudioDataPipeline>)callback;

- (void)initialize;

- (void)onNewAudioData:(AudioDataContainer *)audioData;
@end