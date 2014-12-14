//
//  Connectivity.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "InputSession.h"
#import "OutputSession.h"

typedef enum {
    ERROR_CON,
    OK_CON,
    CONNECTING
} ConnectionStatus;

@protocol ConnectionStatusDelegate
-(void)connectionStatusChange: (ConnectionStatus) status withDescription: (NSString*) description;
@end

@interface ConnectionManager : NSObject<NSStreamDelegate>
@property (nonatomic, readonly) id  connectionStatusDelegate;
@property (nonatomic, readonly) id  inputSession;
- (id) initWithDelegate: (id<ConnectionStatusDelegate>)p_connectionStatusDelegate inputSession: (id<NewDataDelegate>)inputSession outputSession: (OutputSession*)outputSession;
- (void) myMethod;
- (void) connect;
@end



