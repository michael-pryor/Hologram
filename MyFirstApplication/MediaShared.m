//
// Created by Michael Pryor on 10/11/2015.
//

#import "MediaShared.h"
#import "ByteBuffer.h"


@implementation MediaShared {

}
+ (uint) getBatchIdFromByteBuffer:(ByteBuffer*)buffer {
    // Always the second integer.
    return [buffer getUnsignedIntegerAtPosition:sizeof(uint)];
}
@end