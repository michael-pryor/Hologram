//
// Created by Michael Pryor on 21/02/2016.
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
@import AudioToolbox;
#import "AudioShared.h"

@interface AudioCompression : NSObject <AudioDataPipeline, NewPacketDelegate>
- (id)initWithAudioFormat:(AudioStreamBasicDescription)audioFormat outputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding;

- (AudioDataContainer *)getPendingDecompressedData;

- (AudioDataContainer *)getUncompressedItem;

- (AudioDataContainer *)getCompressedItem;

- (void)initialize;

- (void)reset;

- (void)terminate;
@end