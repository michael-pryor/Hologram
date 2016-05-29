//
// Created by Michael Pryor on 27/05/2016.
//

#import "DnsResolver.h"
#import <dns_sd.h>
#import <dns_util.h>
#import "NetworkUtility.h"
#import "Analytics.h"
#import "Signal.h"

static NSString *dnsSaveKey = @"previousDnsResolutions";
static NSString *lastResortResolution = @"192.168.1.92";

@implementation DnsResolver : NSObject {
    Signal *_dnsLookupInProgress;
    NSString *_dnsHost;
    NSTimeInterval _dnsUpdateTimeout;
    DNSServiceRef _serviceRef;
    id <DnsResultNotifier> _resultNotifier;
    Timer* _dnsResolutionTimer;
}
- (id)initWithNotifier:(id <DnsResultNotifier>)resultNotifier dnsHost:(NSString *)dnsHost timeout:(NSTimeInterval)dnsUpdateTimeout {
    self = [super init];
    if (self) {
        _dnsHost = dnsHost;
        _dnsUpdateTimeout = dnsUpdateTimeout;
        _dnsLookupInProgress = [[Signal alloc] initWithFlag:false];
        _resultNotifier = resultNotifier;
        _dnsResolutionTimer = [[Timer alloc] init];
    }
    return self;
}

void getAddrInfoCallBack(DNSServiceRef sdRef, DNSServiceFlags flags, uint32_t interfaceIndex, DNSServiceErrorType errorCode, const char *hostname, const struct sockaddr *address, uint32_t ttl, void *context) {
    DnsResolver *resolverObject = (__bridge DnsResolver *) context;
    if (![resolverObject->_dnsLookupInProgress clear]) {
        return;
    }

    NSString *host = [NetworkUtility retrieveHostFromAddress:address];

    [[Analytics getInstance] pushTimer:resolverObject->_dnsResolutionTimer withCategory:@"setup" name:@"dns_resolution" label:@"normal_lookup"];

    DNSServiceRefDeallocate(resolverObject->_serviceRef);
    [resolverObject storePreviousHostName:host];
    [resolverObject->_resultNotifier onDnsSuccess:host];
};

- (void)startResolvingDns {
    if (![_dnsLookupInProgress signalAll]) {
        return;
    }

    [_dnsResolutionTimer reset];
    DNSServiceErrorType result = DNSServiceGetAddrInfo(&_serviceRef, 0, 0, kDNSServiceProtocol_IPv4, [_dnsHost UTF8String], getAddrInfoCallBack, 0);
    if (result != kDNSServiceErr_NoError) {
        NSLog(@"DNSServiceGetAddrInfo failure");
        [self onDnsResolutionFailure];
    }

    __block DnsResolver* blockDnsResolver = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)_dnsUpdateTimeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (![blockDnsResolver->_dnsLookupInProgress clear]) {
            return;
        }
        DNSServiceRefDeallocate(blockDnsResolver->_serviceRef);

        [blockDnsResolver onDnsResolutionFailure];
    });
}

- (void)storePreviousHostName:(NSString *)resolvedHostName {
    NSDictionary *result = [[NSUserDefaults standardUserDefaults] dictionaryForKey:dnsSaveKey];
    if (result == nil) {
        // This is the first item, so add it and we're done.
        [[NSUserDefaults standardUserDefaults] setObject:@{_dnsHost : resolvedHostName} forKey:dnsSaveKey];
        NSLog(@"Resolved first DNS record [%@] with IP [%@]", _dnsHost, resolvedHostName);
    } else {
        NSString *previouslyResolvedHostName = result[_dnsHost];
        if (previouslyResolvedHostName != nil && [resolvedHostName isEqualToString:previouslyResolvedHostName]) {
            NSLog(@"DNS resolution [%@] to IP [%@] unchanged since last resolve", _dnsHost, resolvedHostName);
            return;
        }

        // Create or overwrite existing entry.
        NSMutableDictionary *mutableDict = [result mutableCopy];
        mutableDict[_dnsHost] = resolvedHostName;
        [[NSUserDefaults standardUserDefaults] setObject:mutableDict forKey:dnsSaveKey];

        if (previouslyResolvedHostName == nil) {
            NSLog(@"Associated a new DNS record [%@] with IP [%@]", _dnsHost, resolvedHostName);
        } else {
            NSLog(@"Overwritten existing DNS record [%@]. Old IP [%@], new IP [%@]", _dnsHost, previouslyResolvedHostName, resolvedHostName);
        }
    }
}

- (NSString *)lookupPreviousHostName {
    NSDictionary *result = [[NSUserDefaults standardUserDefaults] dictionaryForKey:dnsSaveKey];
    if (result == nil) {
        return nil;
    }

    NSString *previouslyResolvedHostName = result[_dnsHost];
    if (previouslyResolvedHostName == nil) {
        return nil;
    }
    NSLog(@"DNS resolved through looking up in storage, [%@] to IP [%@]", _dnsHost, previouslyResolvedHostName);
    [[Analytics getInstance] pushTimer:_dnsResolutionTimer withCategory:@"setup" name:@"dns_resolution" label:@"previous_lookup"];
    return previouslyResolvedHostName;
}

- (void)lookupWithoutNetwork {
    NSString* resolvedDns = [self lookupPreviousHostName];
    if (resolvedDns == nil) {
        resolvedDns = lastResortResolution;
        NSLog(@"As last resort, resolved DNS manually with hard coded value, [%@] to IP [%@]", _dnsHost, resolvedDns);
        [[Analytics getInstance] pushTimer:_dnsResolutionTimer withCategory:@"setup" name:@"dns_resolution" label:@"manual_lookup"];
    }
    [_resultNotifier onDnsSuccess:resolvedDns];
}

- (void)onDnsResolutionFailure {
    [self lookupWithoutNetwork];
}

@end