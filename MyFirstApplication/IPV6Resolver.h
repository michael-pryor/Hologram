//
// Created by Michael Pryor on 04/06/2016.
//

#import <Foundation/Foundation.h>


@interface IPV6Resolver : NSObject
- (id)init;

- (struct addrinfo *)retrieveAddressesFromHost:(NSString *)hostName withPort:(uint)port;
@end