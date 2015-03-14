//
//  SoundEncoding.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 09/03/2015.
//
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioQueue.h>

@interface SoundEncoding : NSObject
- (id) init;
- (void) startCapturing;
- (void) stopCapturing;
- (AudioStreamBasicDescription) getAudioDescription;
@end
