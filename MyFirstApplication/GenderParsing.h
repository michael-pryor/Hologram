//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>


#define MALE 1
#define FEMALE 2
#define BOTH 3

#define INTERESTED_IN_BOTH_SEGMENT_ID 2

@interface GenderParsing : NSObject
+ (uint)parseGenderString:(NSString *)gender;

+ (NSString *)parseGenderSegmentIndexToString:(int)segmentIndex;

+ (int)parseGenderStringToSegmentIndex:(NSString*)genderString;

+ (uint)parseGenderSegmentIndex:(int)segmentIndex;
@end