//
//  NetworkUtility.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 27/06/2015.
//
//

#import "NetworkUtility.h"
#include <ifaddrs.h>
#include <arpa/inet.h>

@implementation NetworkUtility
+ (Boolean)isEqualAddress:(struct sockaddr_in*)addr1 address:(struct sockaddr_in*)addr2 {
    if(addr1->sin_port != addr2->sin_port) {
        return false;
    }
    
    return addr1->sin_addr.s_addr == addr2->sin_addr.s_addr;
}

+ (NSString*)convertPreparedAddress:(uint)address port:(ushort)port{
    ushort convertedPort = ntohs(port);
    struct in_addr addr;
    addr.s_addr = address;
    char * convertedAddress = inet_ntoa(addr);
    NSString * description = [NSString localizedStringWithFormat:@"%s:%d", convertedAddress, convertedPort];
    return description;
}
@end
