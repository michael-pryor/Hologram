//
// Created by Michael Pryor on 10/11/2015.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

@protocol MediaDelayNotifier
- (void)onMediaDelayNotified:(uint)batchId delayMs:(uint)delayMs;
@end

@interface MediaShared : NSObject
+ (uint)getBatchIdFromByteBuffer:(ByteBuffer *)buffer;
@end