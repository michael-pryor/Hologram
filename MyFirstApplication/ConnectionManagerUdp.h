//
//  ConnectionManagerUdp.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerBase.h"
#import "InputSessionBase.h"
#import "ByteBuffer.h"
#import "InputSessionBase.h"

typedef enum {
    U_ERROR,
    U_CONNECTED
} ConnectionStatusUdp;

@protocol ConnectionStatusDelegateUdp
-(void)connectionStatusChangeUdp: (ConnectionStatusUdp) status withDescription: (NSString*) description;
@end

@interface ConnectionManagerUdp : NSObject<ConnectionManagerBase, NewPacketDelegate>
- (id) initWithNewPacketDelegate:(id<NewPacketDelegate>)newPacketDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate connectionDelegate:(id<ConnectionStatusDelegateUdp>)connectionDelegate retryCount:(uint)retryCountMax;
- (void) connectToHost: (NSString*) host andPort: (ushort) port;
- (void) shutdown;
- (Boolean) isConnected;

- (void) sendBuffer:(ByteBuffer*)buffer;
- (void) onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end
