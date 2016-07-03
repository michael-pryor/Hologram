//
// Created by Michael Pryor on 02/07/2016.
//

#import "DobParsing.h"

NSDateFormatter *textBoxDateFormatter;

@implementation DobParsing {

}

+ (void)initialize {
    if (self == [DobParsing class]) {
        textBoxDateFormatter = [[NSDateFormatter alloc] init];
        [textBoxDateFormatter setDateFormat:@"yyyy-MM-dd"];
    }
}

+ (NSDate *)getDateObjectFromTextBoxString:(NSString *)dob {
    return [textBoxDateFormatter dateFromString:dob];
}

+ (NSString *)getTextBoxStringFromDateObject:(NSDate *)dob {
    return [textBoxDateFormatter stringFromDate:dob];
}

+ (NSDate *)getDateObjectFromFacebookString:(NSString *)dob {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

    if ([dob length] == 4) {
        [dateFormatter setDateFormat:@"yyyy"];
    } else if ([dob length] == 5) {
        [dateFormatter setDateFormat:@"MM/dd"];
    } else {
        [dateFormatter setDateFormat:@"MM/dd/yyyy"];
    }

    return [dateFormatter dateFromString:dob];
}

+ (uint)getAgeFromDateObject:(NSDate *)date {
    if (date == nil) {
        return 0;
    }

    NSDate *now = [NSDate date];
    NSDateComponents *ageComponents = [[NSCalendar currentCalendar]
            components:NSCalendarUnitYear
              fromDate:date
                toDate:now
               options:0];
    NSInteger age = [ageComponents year];
    return (uint) age;
}
@end