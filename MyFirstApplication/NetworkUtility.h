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
+ (Boolean)isEqualAddress:(struct sockaddr *)rawAddr1 address:(struct sockaddr *)rawAddr2;

+ (NSString *)convertPreparedAddress:(uint)address port:(ushort)port;

+ (NSString *)convertPreparedHostName:(uint)address;

+ (NSString *)retrieveHostFromBytes:(const void*)bytes length:(uint)length;

+ (void)setPortOfAddr:(struct sockaddr *)rawAddr to:(uint)port;
@end
