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
+ (Boolean)isEqualAddress:(struct sockaddr *)rawAddr1 address:(struct sockaddr *)rawAddr2 {
    if (rawAddr1->sa_family != rawAddr2->sa_family) {
        return false;
    }

    // IPv4
    if (rawAddr1->sa_family == AF_INET) {
        struct sockaddr_in* addr1 = (struct sockaddr_in*)rawAddr1;
        struct sockaddr_in* addr2 = (struct sockaddr_in*)rawAddr2;
        if (addr1->sin_port != addr2->sin_port) {
            return false;
        }

        return addr1->sin_addr.s_addr == addr2->sin_addr.s_addr;
    }

    // IPv6
    if (rawAddr1->sa_family == AF_INET6) {
        struct sockaddr_in6* addr1 = (struct sockaddr_in6*)rawAddr1;
        struct sockaddr_in6* addr2 = (struct sockaddr_in6*)rawAddr2;

        size_t size = sizeof(struct in6_addr);
        return memcmp(&addr1->sin6_addr, &addr2->sin6_addr, size) == 0 && addr1->sin6_port == addr2->sin6_port;
    }

    // Don't know what we're dealing with here!
    return false;
}

+ (void)setPortOfAddr:(struct sockaddr *)rawAddr to:(uint)port {
    // IPv4
    if (rawAddr->sa_family == AF_INET) {
        struct sockaddr_in* addr = (struct sockaddr_in*)rawAddr;
        addr->sin_port = htons(port);
        return;
    }

    // IPv6
    if (rawAddr->sa_family == AF_INET6) {
        struct sockaddr_in6* addr = (struct sockaddr_in6*)rawAddr;
        addr->sin6_port = htons(port);
    }
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
