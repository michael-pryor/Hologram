//
// Created by Michael Pryor on 21/02/2016.
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
@import AudioToolbox;
#import "AudioShared.h"
#import "BlockingQueue.h"
#import "AudioSessionInteractions.h"

@interface AudioCompression : NSObject <AudioDataPipeline, NewPacketDelegate>
- (id)initWithUncompressedAudioFormat:(AudioStreamBasicDescription)uncompressedAudioFormat uncompressedAudioFormatEx:(AudioFormatProcessResult)uncompressedAudioFormatEx outputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding outboundQueue:(BlockingQueue *)outboundQueue sequenceGapNotifier:(id <SequenceGapNotification>)sequenceGapNotifier;

- (AudioDataContainer *)getPendingDecompressedData;

- (AudioDataContainer *)getUncompressedItem;

- (AudioDataContainer *)getCompressedItem;

- (void)initialize;

- (void)reset;

- (void)terminate;
@end