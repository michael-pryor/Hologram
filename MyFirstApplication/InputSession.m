//
//  InputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "InputSession.h"

@implementation InputSessionTCP
@synthesize recvBuffer;
- (void)onNewData: (uint)length {
    [recvBuffer moveCursorForwards:length];
}
- (ByteBuffer*)getDestinationBuffer {
    return recvBuffer;
}
@end
