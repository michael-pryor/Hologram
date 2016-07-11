//
// Created by Michael Pryor on 11/07/2016.
//

#import "ViewStringFormatting.h"


@implementation ViewStringFormatting {

}
+ (float)getKarmaRatioFromValue:(uint)karmaValue maximum:(uint)karmaMaximum {
    float karmaFloatValue = karmaValue;
    float karmaFloatMax = karmaMaximum;
    return karmaFloatValue / karmaFloatMax;
}

+ (NSString *)getStringFromDistance:(uint)distance {
    NSString *distanceString;
    if (distance <= 1) {
        distanceString = @"< 1";
    } else if (distance > 15000) {
        distanceString = @"> 15000";
    } else {
        distanceString = [NSString stringWithFormat:@"%u", distance];
    }
    return [NSString stringWithFormat:@"%@ km away", distanceString];;
}

+ (NSString*)getAgeString:(uint)age {
    if (age > 150) {
        age = 150;
    }

    return [NSString stringWithFormat:@"%u", age];
}

+ (void)updateKarmaUsingProgressView:(UIProgressView *)progressView ratio:(float)ratio {
    if (ratio > 0.9) {
        [progressView setTintColor:[UIColor greenColor]];
    } else if (ratio < 0.3) {
        [progressView setTintColor:[UIColor redColor]];
    } else {
        [progressView setTintColor:[UIColor blueColor]];
    }
    [progressView setProgress:ratio animated:false];
}
@end