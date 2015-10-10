//
//  LoginProvider.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/07/2015.
//
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

@protocol LoginProvider
- (ByteBuffer *)getLoginBuffer;
@end
