//
// Created by Michael Pryor on 27/05/2016.
//

#import <Foundation/Foundation.h>

@protocol DnsResultNotifier
- (void)onDnsSuccess:(NSString *)resolvedHostName;
@end

@interface DnsResolver : NSObject
- (id)initWithDnsHost:(NSString *)dnsHost timeout:(NSTimeInterval)dnsUpdateTimeout resultNotifier:(id <DnsResultNotifier>)resultNotifier;

- (void)startResolvingDns;

- (void)lookupWithoutNetwork;
@end