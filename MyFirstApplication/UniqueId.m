//
// Created by Michael Pryor on 02/07/2016.
//

#import "UniqueId.h"
#import "KeychainItemWrapper.h"
static UniqueId *instance = nil;

static NSString * _keychainApplicationName =  @"UserUUID_HOLOGRAM";

static NSString * _defaultsIdStringKey = @"UUID_Account";
static NSString * _defaultsIdStringVerified = @"UUID_Account_Verified";

/**
 * Maintain a unique ID to be associated with this installation of the app on this device only.
 *
 * First query memory if we've already loaded something.
 * Then go to defaults. If this fails goto key chain. Key chain is less reliable, but
 * is preserved after reinstall of application.
 */
@implementation UniqueId {
    NSString *_currentUniqueId;
    bool _isValidated;
}

- (id)init {
    self = [super init];
    if (self) {
        _currentUniqueId = [UniqueId pullUUIDForcingNew:false];
        _isValidated = [UniqueId isValidatedUUID];
    }
    return self;
}

- (NSString *)getUUID {
    return _currentUniqueId;
}

- (NSString*)refreshUUID {
    @synchronized (self) {
        _currentUniqueId = [UniqueId pullUUIDForcingNew:true];
        _isValidated = false;
        return _currentUniqueId;
    }
}

- (void)onValidatedUUID {
    @synchronized(self) {
        if (!_isValidated) {
            _isValidated = true;
            [UniqueId writeValidationUUID:true];
        }
    }
}

- (bool)isValidatedUUID {
    return _isValidated;
}

+ (bool)isValidatedUUID {
    NSUserDefaults * defaults = [self defaults];
    KeychainItemWrapper *keyChain = [self keyChain];

    if ([defaults objectForKey:_defaultsIdStringVerified] != nil) {
        return [defaults boolForKey:_defaultsIdStringVerified];
    }

    NSNumber *idValidated = [keyChain objectForKey:(__bridge id) (kSecAttrIsInvisible)];
    if (idValidated == nil) {
        return false;
    }
    return [idValidated boolValue];
}

+ (void)writeValidationUUID:(bool)isValidated {
    NSUserDefaults * defaults = [self defaults];
    KeychainItemWrapper *keyChain = [self keyChain];

    [defaults setBool:isValidated forKey:_defaultsIdStringVerified];
    [keyChain setObject:@(isValidated) forKey:(__bridge id) (kSecAttrIsInvisible)];
}

+ (NSString *)pullUUIDForcingNew:(bool)forceNew {
    NSUserDefaults * defaults = [self defaults];
    KeychainItemWrapper * keyChain = [self keyChain];

    NSString * existingId = [defaults stringForKey:_defaultsIdStringKey];

    if (existingId == nil) {
        existingId = [keyChain objectForKey:(__bridge id) (kSecAttrAccount)];

        if (existingId != nil) {
            NSLog(@"Retrieved existing UUID [%@] from keychain", existingId);
            [defaults setObject:existingId forKey:_defaultsIdStringKey];
        }
    }

    NSString *UUID;
    if (existingId == nil || [existingId length] == 0 || forceNew) {
        // Unique ID used to identify this user going forwards.
        UUID = [[NSUUID UUID] UUIDString];
        [defaults setObject:UUID forKey:_defaultsIdStringKey];
        [keyChain setObject:UUID forKey:(__bridge id) (kSecAttrAccount)];

        [self writeValidationUUID:false];
        NSLog(@"Associated with UUID [%@]", UUID);
    } else {
        UUID = existingId;
        NSLog(@"Retrieved existing UUID [%@]", UUID);
    }

    return UUID;
}

+ (NSUserDefaults*)defaults {
    return [NSUserDefaults standardUserDefaults];
}

+ (KeychainItemWrapper*)keyChain {
    return [[KeychainItemWrapper alloc] initWithIdentifier:_keychainApplicationName accessGroup:nil];
}

+ (UniqueId *)getUniqueIdInstance {
    @synchronized (self) {
        if (instance == nil) {
            instance = [[UniqueId alloc] init];
        }
        
        return instance;
    }
}

@end