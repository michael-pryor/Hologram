//
// Created by Michael Pryor on 27/05/2016.
//

#import <Foundation/Foundation.h>

@protocol DnsResultNotifier
- (void)onDnsSuccess:(NSString *)resolvedHostName;
@end

@interface DnsResolver : NSObject
- (id)initWithNotifier:(id <DnsResultNotifier>)resultNotifier dnsHost:(NSString *)dnsHost timeout:(NSTimeInterval)dnsUpdateTimeout;

- (void)startResolvingDns;

- (void)lookupWithoutNetwork;
@end