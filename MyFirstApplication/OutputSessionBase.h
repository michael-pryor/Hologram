//
//  OutputSessionBase.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 20/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

@protocol OutputSessionBase
- (void) sendPacket: (ByteBuffer*)buffer;
@end
