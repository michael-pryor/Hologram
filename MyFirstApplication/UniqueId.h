//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>


@interface UniqueId : NSObject
- (NSString *)getUUID;

- (NSString*)refreshUUID;

- (bool)isValidatedUUID;

- (void)onValidatedUUID;

+ (UniqueId *)getUniqueIdInstance;
@end