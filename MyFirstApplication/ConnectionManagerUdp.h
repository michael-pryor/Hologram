//
//  ConnectionManagerUdp.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

@interface ConnectionManagerUdp : NSObject
- (void) connectToHost: (NSString*) host andPort: (ushort) port;
- (void) sendBuffer: (ByteBuffer*)buffer;
@end
