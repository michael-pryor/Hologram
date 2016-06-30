//
//  HologramLogin.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/07/2015.
//
//

#import <Foundation/Foundation.h>
#import "LoginProvider.h"
#import "GpsState.h"

@interface HologramLogin : NSObject <LoginProvider>
- (id)initWithGpsState:(GpsState *)gpsState regenerateKarmaReceipt:(NSData *)receipt;

- (ByteBuffer *)getLoginBuffer;

- (void)clearKarmaRegeneration;
@end
