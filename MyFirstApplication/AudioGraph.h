//
// Created by Michael Pryor on 17/02/2016.
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
#import "AudioShared.h"
@import AudioToolbox;

@interface AudioGraph : NSObject <NewPacketDelegate, AudioDataPipeline, SequenceGapNotification>
- (AudioUnit)getAudioProducer;

- (void)initialize;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding sequenceGapNotifier:(id <SequenceGapNotification>)sequenceGapNotifier timeInQueueNotifier:(id <TimeInQueueNotification>)timeInQueueNotifier;

- (void)stop;

- (void)start;

- (bool)isRunning;
@end