//
//  Connectivity.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>

typedef enum {
    ERROR,
    OK,
    CONNECTING
} ConnectionStatus;

@protocol ConnectionStatusDelegate
-(void)connectionStatusChange: (ConnectionStatus) status withDescription: (NSString*) description;
@end

@interface ConnectionManager : NSObject<NSStreamDelegate>
@property (nonatomic, assign) id  connectionStatusDelegate;
- (id) init: (id<ConnectionStatusDelegate>) connectionStatusDelegate;
- (void) myMethod;
- (void) connect;
@end



