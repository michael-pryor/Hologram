//
// Created by Michael Pryor on 10/11/2015.
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"


@interface MediaShared : NSObject
+ (uint) getBatchIdFromByteBuffer:(ByteBuffer*)buffer;
@end