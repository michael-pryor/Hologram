//
// Created by Michael Pryor on 02/07/2016.
//

#import "UniqueId.h"
#import "KeychainItemWrapper.h"


@implementation UniqueId {

}

+ (NSString *)pullUUID {
    return [self pullUUIDForcingNew:false];
}

+ (NSString*)refreshUUID {
    return [self pullUUIDForcingNew:true];
}

+ (NSString *)pullUUIDForcingNew:(bool)forceNew {
    KeychainItemWrapper *keychain = [[KeychainItemWrapper alloc] initWithIdentifier:@"UserUUID_HOLOGRAM" accessGroup:nil];
    NSString *existingId = [keychain objectForKey:(__bridge id) (kSecAttrAccount)];
    NSString *UUID;
    if (existingId == nil || forceNew) {
        // Unique ID used to identify this user going forwards.
        UUID = [[NSUUID UUID] UUIDString];
        [keychain setObject:UUID forKey:(__bridge id) (kSecAttrAccount)];
        NSLog(@"Associated with UUID [%@]", UUID);
    } else {
        UUID = existingId;
        NSLog(@"Retrieved existing UUID [%@]", UUID);
    }

    return UUID;
}

@end