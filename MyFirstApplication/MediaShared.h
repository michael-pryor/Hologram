//
// Created by Michael Pryor on 10/11/2015.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

enum MediaType {
    // Video heavy packet loss (we don't count chunks missing from batches).
    VIDEO,

    // Audio packet loss.
    AUDIO,

    // Queues which stay too full for an extended period are cleared, to prevent audio delay (like a clearing cars out of a traffic jam).
    AUDIO_QUEUE_RESET
};
typedef enum MediaType MediaType;

@protocol MediaDataLossNotifier
- (void)onMediaDataLossFromSender:(MediaType)mediaType;
@end