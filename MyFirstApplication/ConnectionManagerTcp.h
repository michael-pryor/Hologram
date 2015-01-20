//
//  Connectivity.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "OutputSessionTcp.h"
#import "InputSessionBase.h"
#import "ConnectionManagerBase.h"

typedef enum {
    ERROR_CON,
    OK_CON,
    CONNECTING
} ConnectionStatusTcp;

@protocol ConnectionStatusDelegateTcp
-(void)connectionStatusChange: (ConnectionStatusTcp) status withDescription: (NSString*) description;
@end

@interface ConnectionManagerTcp : NSObject<NSStreamDelegate, ConnectionManagerBase>
@property (nonatomic, readonly) id connectionStatusDelegate;
- (id) initWithDelegate:(id<ConnectionStatusDelegateTcp>)connectionStatusDelegate inputSession:(id<NewDataDelegate>)inputSession outputSession:(OutputSessionTcp*)outputSession;
- (void) connectToHost: (NSString*)host andPort: (ushort)port;
- (void) shutdown;
- (Boolean) isConnected;
@end



