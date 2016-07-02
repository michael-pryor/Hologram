//
// Created by Michael Pryor on 02/07/2016.
//

#import "DobParsing.h"


@implementation DobParsing {

}
+ (NSString*)getDateStringFromDateObject:(NSDate*)date {
    NSDateFormatter *dateFormatter=[[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd/yyyy"];
    return [dateFormatter stringFromDate:date];
}

+ (NSDate*)getDateObjectFromString:(NSString*)dob {
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