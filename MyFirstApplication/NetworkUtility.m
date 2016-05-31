//
//  NetworkUtility.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 27/06/2015.
//
//

#import "NetworkUtility.h"
#include <arpa/inet.h>

@implementation NetworkUtility
+ (Boolean)isEqualAddress:(struct sockaddr_in *)addr1 address:(struct sockaddr_in *)addr2 {
    if (addr1->sin_port != addr2->sin_port) {
        return false;
    }

    return addr1->sin_addr.s_addr == addr2->sin_addr.s_addr;
}

+ (NSString *)convertPreparedHostName:(uint)address {
    struct in_addr addr;
    memset(&addr, 0, sizeof(addr));
    addr.s_addr = address;
    char *convertedAddress = inet_ntoa(addr);
    return [NSString localizedStringWithFormat:@"%s", convertedAddress];
}

+ (NSString *)convertPreparedAddress:(uint)address port:(ushort)port {
    ushort convertedPort = ntohs(port);
    struct in_addr addr;
    addr.s_addr = address;
    char *convertedAddress = inet_ntoa(addr);
    NSString *description = [NSString localizedStringWithFormat:@"%s:%d", convertedAddress, convertedPort];
    return description;
}

+ (NSString *)retrieveHostFromBytes:(const void*)bytes length:(uint)length {
    if (length != sizeof(int)) {
        NSLog(@"Could not parse raw bytes into host name, invalid size of %d vs expected size of %lu", length, sizeof(int));
        return nil;
    }

    uint resultNetwork;
    memcpy(&resultNetwork, bytes, sizeof(int));

    return [NetworkUtility convertPreparedHostName:resultNetwork];
}
@end
