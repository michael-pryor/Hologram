//
//  ConnectionManagerUdp.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerBase.h"
#import "OutputSessionBase.h"
#import "ByteBuffer.h"
#import "InputSessionBase.h"

@interface ConnectionManagerUdp : NSObject<ConnectionManagerBase, OutputSessionBase>
- (id) initWithNewPacketDelegate:(id<NewPacketDelegate>)newPacketDelegate;
- (void) connectToHost: (NSString*) host andPort: (ushort) port;
- (void) shutdown;
- (Boolean) isConnected;

- (void) sendPacket: (ByteBuffer*)buffer;
@end
