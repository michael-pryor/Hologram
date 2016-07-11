//
// Created by Michael Pryor on 11/07/2016.
//

#import <Foundation/Foundation.h>


@interface ViewStringFormatting : NSObject
+ (float)getKarmaRatioFromValue:(uint)karmaValue maximum:(uint)karmaMaximum;

+ (NSString *)getStringFromDistance:(uint)distance;

+ (NSString*)getAgeString:(uint)age;
@end