//
//  ConnectionManagerBase.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 20/01/2015.
//
//

#import <Foundation/Foundation.h>

@protocol ConnectionManagerBase
- (void) connectToHost: (NSString*) host andPort: (ushort) port;
- (void) shutdown;
- (Boolean) isConnected;
@end
