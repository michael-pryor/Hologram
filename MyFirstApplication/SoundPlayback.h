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

@interface SoundPlayback : NSObject<NewPacketDelegate>
- (id)initWithAudioDescription:(AudioStreamBasicDescription*)description secondsPerBuffer:(Float64)seconds numBuffers:(uint)numBuffers restartPlaybackThreshold:(uint)restartPlayback maxPendingAmount:(uint)maxAmount;
- (ByteBuffer*) getSoundPacketToPlay;
- (void) shutdown;
- (void) start;
@end
