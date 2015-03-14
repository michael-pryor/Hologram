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

@interface SoundPlayback : NSObject
- (ByteBuffer*) getSoundPacketToPlay;
@end
