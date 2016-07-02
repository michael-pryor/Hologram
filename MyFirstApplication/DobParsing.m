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

+ (uint)getAgeFromDateOfBirth:(NSString *)dob {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

    if ([dob length] == 4) {
        [dateFormatter setDateFormat:@"yyyy"];
    } else if ([dob length] == 5) {
        [dateFormatter setDateFormat:@"MM/dd"];
    } else {
        [dateFormatter setDateFormat:@"MM/dd/yyyy"];
    }

    NSDate *date = [dateFormatter dateFromString:dob];


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