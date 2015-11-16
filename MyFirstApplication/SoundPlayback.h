//
//  SoundPlayback.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioQueue.h>
#import "ByteBuffer.h"
#import "InputSessionBase.h"
#import "MediaShared.h"

@protocol SoundPlaybackDelegate
- (void)playbackStopped;

- (void)playbackStarted;
@end

@interface SoundPlayback : NSObject <NewPacketDelegate>
- (id)initWithAudioDescription:(AudioStreamBasicDescription *)description numBuffers:(uint)numBuffers maxPendingAmount:(uint)maxAmount soundPlaybackDelegate:(id <SoundPlaybackDelegate>)soundPlaybackDelegate mediaDelayDelegate:(id <MediaDelayNotifier>)mediaDelayDelegate;

- (void)shutdown;

- (void)initialize;

- (void)startPlayback;

- (void)stopPlayback;

- (void)setMagicCookie:(Byte*)magicCookie size:(int)size;

- (bool)shouldReturnBuffer;
@end
