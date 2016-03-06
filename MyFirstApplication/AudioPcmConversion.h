//
// Created by Michael Pryor on 05/03/2016.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;
#import "AudioShared.h"
#import "BlockingQueue.h"

@interface AudioPcmConversion : NSObject
- (id)initWithDescription:(NSString*)humanDescription inputFormat:(AudioStreamBasicDescription *)inputFormat outputFormat:(AudioStreamBasicDescription *)outputFormat outputResult:(id <AudioDataPipeline>)callback numFramesPerOperation:(UInt32)numFrames inboundQueue:(BlockingQueue*)queue;

- (void)initialize;

- (void)onNewAudioData:(AudioDataContainer *)audioData;

- (void)terminate;

- (void)reset;
@end