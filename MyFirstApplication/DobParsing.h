//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>


@interface DobParsing : NSObject
+ (NSString*)getDateStringFromDateObject:(NSDate*)date;

+ (NSDate*)getDateObjectFromString:(NSString*)dob;

+ (uint)getAgeFromDateObject:(NSDate *)date;
@end