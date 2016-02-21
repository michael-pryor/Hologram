//
// Created by Michael Pryor on 21/02/2016.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;

@interface AudioDataContainer : NSObject
@property(readonly) UInt32 numFrames;
@property(readonly) AudioBufferList *audioList;

- (id)initWithNumFrames:(UInt32)numFrames audioList:(AudioBufferList *)audioList;
@end

@protocol AudioDataPipeline
- (void)onNewAudioData:(AudioDataContainer *)audioData;
@end

@interface AudioCompression : NSObject <AudioDataPipeline>
- (id)initWithAudioFormat:(AudioStreamBasicDescription)audioFormat;

- (AudioDataContainer *)getPendingDecompressedData;
@end