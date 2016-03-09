//
// Created by Michael Pryor on 10/11/2015.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

enum MediaType {
    VIDEO,
    AUDIO
};
typedef enum MediaType MediaType;

@protocol MediaDelayNotifier
- (void)onMediaDataLossFromSender:(MediaType)mediaType;
@end