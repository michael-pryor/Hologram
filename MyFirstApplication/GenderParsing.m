//
// Created by Michael Pryor on 02/07/2016.
//

#import "GenderParsing.h"


@implementation GenderParsing {

}

+ (uint)parseGenderString:(NSString *)gender {
    if (gender == nil) {
        return BOTH;
    } else if ([@"male" isEqualToString:gender]) {
        return MALE;
    } else if ([@"female" isEqualToString:gender]) {
        return FEMALE;
    } else {
        // Facebook API tells us that this can't happen.
        NSLog(@"Unknown gender: %@", gender);
        return BOTH;
    }
}

+ (NSString *)parseGenderSegmentIndexToString:(int)segmentIndex {
    if (segmentIndex == 0) {
        return @"male";
    } else if (segmentIndex == 1) {
        return @"female";
    } else if (segmentIndex == INTERESTED_IN_BOTH_SEGMENT_ID) {
        return nil;
    } else {
        [NSException raise:@"Invalid interested in segment index" format:@"segment index %d is invalid", segmentIndex];
    }
}

+ (int)parseGenderStringToSegmentIndex:(NSString*)genderString {
    if ([@"male" isEqualToString:genderString]) {
        return 0;
    } else if ([@"female" isEqualToString:genderString]) {
        return 1;
    } else{
        return INTERESTED_IN_BOTH_SEGMENT_ID;
    }
}

+ (uint)parseGenderSegmentIndex:(int)segmentIndex {
    return [self parseGenderString:[self parseGenderSegmentIndexToString:segmentIndex]];
}
@end