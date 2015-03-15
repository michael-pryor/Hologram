//
//  SoundEncoding.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 09/03/2015.
//
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioQueue.h>
#import "InputSessionBase.h"

@interface SoundEncoding : NSObject
- (id) init;
- (id) initWithOutputSession: (id<NewPacketDelegate>)output;
- (void) startCapturing;
- (void) stopCapturing;
- (AudioStreamBasicDescription) getAudioDescription;
- (void) setOutputSession: (id<NewPacketDelegate>)output;
- (void) start;
@end
