//
//  NetworkUtility.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 27/06/2015.
//
//

#import <Foundation/Foundation.h>
#include <sys/socket.h>
#include <netinet/in.h>

@interface NetworkUtility : NSObject
+ (Boolean)isEqualAddress:(struct sockaddr_in*)addr1 address:(struct sockaddr_in*)addr2;
+ (NSString*)convertPreparedAddress:(uint)address port:(ushort)port;
+ (NSString*)convertPreparedHostName:(uint)address;
@end
