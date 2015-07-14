//
//  QuarkLogin.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/07/2015.
//
//

#import <Foundation/Foundation.h>
#import "LoginProvider.h"




@interface QuarkLogin : NSObject<LoginProvider>
- (ByteBuffer*)getLoginBuffer;
@end
