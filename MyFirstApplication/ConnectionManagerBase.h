//
//  ConnectionManagerBase.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 20/01/2015.
//
//

#import <Foundation/Foundation.h>

@protocol ConnectionManagerBase
- (void)shutdown;

- (Boolean)isConnected;
@end
