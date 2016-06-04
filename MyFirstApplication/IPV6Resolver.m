//
// Created by Michael Pryor on 04/06/2016.
//

#import "IPV6Resolver.h"
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#import "NetworkUtility.h"

@implementation IPV6Resolver {
    struct addrinfo *_result;

    struct addrinfo _cachedBackupResult;
    struct sockaddr_in _cachedBackupAddress;
}

- (id)init {
    self = [super init];
    if (self) {
        _result = nil;
    }
    return self;
}

- (struct addrinfo *)retrieveAddressesFromHost:(NSString *)hostName withPort:(uint)port {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));

    if (_result != nil) {
        freeaddrinfo(_result);
        _result = nil;
    }

    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_DEFAULT;

    const char * portStr = [[NSString stringWithFormat:@"%i", port] cStringUsingEncoding:NSUTF8StringEncoding];

    int error = getaddrinfo([hostName cStringUsingEncoding:NSUTF8StringEncoding], NULL, &hints, &_result);
    if (error) {
        return [self onError:error host:hostName port:port];
    }

    // AI_NUMERICSERV does not appear to work, so we do it manually.
    struct addrinfo * address;
    for (address = _result; address != nil; address = address->ai_next) {
        [NetworkUtility setPortOfAddr:address->ai_addr to:port];
    }

    return _result;
}

- (struct addrinfo *)onError:(int)resultCode host:(NSString*)host port:(uint)port {
    NSLog(@"getaddrinfo error: %i", resultCode);

    memset(&_cachedBackupAddress, 0, sizeof(_cachedBackupAddress));
    _cachedBackupAddress.sin_family = AF_INET;
    _cachedBackupAddress.sin_addr.s_addr = INADDR_ANY;

    _cachedBackupAddress.sin_port = htons(port);
    _cachedBackupAddress.sin_addr.s_addr = inet_addr([host UTF8String]);
    _cachedBackupResult.ai_addr = (struct sockaddr *) &_cachedBackupAddress;
    _cachedBackupResult.ai_addrlen = sizeof(_cachedBackupAddress);
    _cachedBackupResult.ai_next = nil;
    _cachedBackupResult.ai_family = AF_INET;
    _cachedBackupResult.ai_protocol = 0;
    _cachedBackupResult.ai_flags = AI_DEFAULT;
    _cachedBackupResult.ai_canonname = 0;
    _cachedBackupResult.ai_socktype = SOCK_DGRAM;
    return &_cachedBackupResult;
}
@end