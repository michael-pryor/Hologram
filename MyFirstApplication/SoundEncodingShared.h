//
//  SoundEncodingShared.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioQueue.h>
//!pla error; indicates audio no longer playing. i.e. OS paused it.
#define ERR_NOT_PLAYING 561015905

NSString *NSStringFromOSStatus(OSStatus errCode);

bool HandleResultOSStatus(OSStatus errCode, NSString *performing, bool fatal);

Float64 calculateBufferSize(AudioStreamBasicDescription *audioDescription, Float64 numSecondsPerBuffer);