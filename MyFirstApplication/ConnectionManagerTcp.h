//
//  Connectivity.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "OutputSessionTcp.h"
#import "InputSessionTcp.h"
#import "InputSessionBase.h"
#import "ConnectionManagerBase.h"

typedef enum {
    T_ERROR,
    T_CONNECTED,
    T_CONNECTING
} ConnectionStatusTcp;

@protocol ConnectionStatusDelegateTcp
-(void)connectionStatusChangeTcp: (ConnectionStatusTcp) status withDescription: (NSString*) description;
@end

@interface ConnectionManagerTcp : NSObject<NSStreamDelegate, ConnectionManagerBase>
@property (nonatomic, readonly) id connectionStatusDelegate;
- (id) initWithConnectionStatusDelegate:(id<ConnectionStatusDelegateTcp>)connectionStatusDelegate inputSession:(InputSessionTcp*)inputSession outputSession:(OutputSessionTcp*)outputSession;
- (void) connectToHost: (NSString*)host andPort: (ushort)port;
- (void) shutdown;
- (Boolean) isConnected;
@end



