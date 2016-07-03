//
// Created by Michael Pryor on 02/07/2016.
//

#import "UniqueId.h"
#import "KeychainItemWrapper.h"
static UniqueId *instance = nil;

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
    KeychainItemWrapper *keychain = [[KeychainItemWrapper alloc] initWithIdentifier:@"UserUUID_HOLOGRAM" accessGroup:nil];
    NSNumber *idValidated = [keychain objectForKey:(__bridge id) (kSecAttrIsInvisible)];
    if (idValidated == nil) {
        return false;
    }
    return [idValidated boolValue];
}

+ (void)writeValidationUUID:(bool)isValidated {
    KeychainItemWrapper *keychain = [[KeychainItemWrapper alloc] initWithIdentifier:@"UserUUID_HOLOGRAM" accessGroup:nil];
    [keychain setObject:@(isValidated) forKey:(__bridge id) (kSecAttrIsInvisible)];
}

+ (NSString *)pullUUIDForcingNew:(bool)forceNew {
    KeychainItemWrapper *keychain = [[KeychainItemWrapper alloc] initWithIdentifier:@"UserUUID_HOLOGRAM" accessGroup:nil];
    NSString *existingId = [keychain objectForKey:(__bridge id) (kSecAttrAccount)];

    NSString *UUID;
    if (existingId == nil || [existingId length] == 0 || forceNew) {
        // Unique ID used to identify this user going forwards.
        UUID = [[NSUUID UUID] UUIDString];
        [keychain setObject:UUID forKey:(__bridge id) (kSecAttrAccount)];

        [self writeValidationUUID:false];
        NSLog(@"Associated with UUID [%@]", UUID);
    } else {
        UUID = existingId;
        NSLog(@"Retrieved existing UUID [%@]", UUID);
    }

    return UUID;
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