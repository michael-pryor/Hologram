//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>


@interface DobParsing : NSObject
+ (NSString*)getTextBoxStringFromDateObject:(NSDate*)date;

+ (NSDate*)getDateObjectFromFacebookString:(NSString*)dob;

+ (uint)getAgeFromDateObject:(NSDate *)date;

+ (NSDate *)getDateObjectFromTextBoxString:(NSString *)dob;
@end