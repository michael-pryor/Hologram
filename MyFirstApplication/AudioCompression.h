//
// Created by Michael Pryor on 21/02/2016.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;

void printAudioBufferList(AudioBufferList *audioList, NSString* description);

@interface AudioDataContainer : NSObject
@property UInt32 numFrames;
@property AudioBufferList *audioList;

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList;
@end

@protocol AudioDataPipeline
- (void)onNewAudioData:(AudioDataContainer *)audioData;
@end

@interface AudioCompression : NSObject <AudioDataPipeline>
@property uint numFramesRemaining;

- (id)initWithAudioFormat:(AudioStreamBasicDescription)audioFormat;

- (AudioDataContainer *)getPendingDecompressedData;

- (AudioDataContainer *)getUncompressedItem;

- (void)initialize;
@end