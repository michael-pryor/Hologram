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

@interface SoundMicrophone : NSObject
- (id)initWithOutputSession:(id <NewPacketDelegate>)output numBuffers:(uint)numBuffers leftPadding:(uint)padding;

- (void)startCapturing;

- (void)stopCapturing;

- (AudioStreamBasicDescription *)getAudioDescription;

- (void)setOutputSession:(id <NewPacketDelegate>)output;

- (void)initialize;

- (Byte*)getMagicCookie;

- (int)getMagicCookieSize;
@end
