//
//  SoundEncodingShared.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioQueue.h>

NSString *NSStringFromOSStatus(OSStatus errCode);

bool HandleResultOSStatus(OSStatus errCode, NSString *performing, bool shouldLogSuccess);
