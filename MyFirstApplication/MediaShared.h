//
// Created by Michael Pryor on 10/11/2015.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

@protocol MediaDelayNotifier
- (void)onMediaDelayNotified:(uint)delayMs;
@end