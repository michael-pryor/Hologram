//
// Created by Michael Pryor on 02/07/2016.
//

#import "NameParsing.h"


@implementation NameParsing {

}
+ (NSString *)getShortNameAndBuildLongName:(NSMutableString *)outLongName firstName:(NSString *)firstName middleName:(NSString *)middleName lastName:(NSString *)lastName {
    NSString *humanShortName = nil;

    NSString *seperator = @" ";
    Boolean setShortName = false;
    if (firstName != nil) {
        [outLongName appendString:firstName];
        [outLongName appendString:seperator];
        humanShortName = firstName;
        setShortName = true;

    }

    if (middleName != nil) {
        [outLongName appendString:middleName];
        [outLongName appendString:seperator];
    }

    if (lastName != nil) {
        [outLongName appendString:lastName];
        [outLongName appendString:seperator];

        if (!setShortName) {
            humanShortName = lastName;
            setShortName = true;
        }
    }

    if (!setShortName) {
        if (middleName != nil) {
            humanShortName = middleName;
            setShortName = true;
        } else {
            humanShortName = @"?";
        }
    } else {
        // Delete the last character.
        // I know.. dat syntax...
        [outLongName deleteCharactersInRange:NSMakeRange([outLongName length] - 1, 1)];
    }
    return humanShortName;
}
@end