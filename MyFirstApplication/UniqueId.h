//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>


@interface UniqueId : NSObject
+ (NSString *)pullUUID;

+ (NSString*)refreshUUID;

+ (NSString *)pullUUIDForcingNew:(bool)forceNew;
@end