//
// Created by Michael Pryor on 05/03/2016.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;
#import "AudioShared.h"
#import "BlockingQueue.h"
#import "AudioSessionInteractions.h"

@interface AudioPcmConversion : NSObject
- (id)initWithDescription:(NSString *)humanDescription inputFormat:(AudioStreamBasicDescription)inputFormat outputFormat:(AudioStreamBasicDescription)outputFormat outputFormatEx:(AudioFormatProcessResult)outputFormatEx outputResult:(id <AudioDataPipeline>)callback inboundQueue:(BlockingQueue *)queue  sequenceGapNotifier:(id <SequenceGapNotification>)sequenceGapNotifier;

- (void)initialize;

- (void)onNewAudioData:(AudioDataContainer *)audioData;

- (void)terminate;

- (void)reset;
@end