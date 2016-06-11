//
// Created by Michael Pryor on 11/06/2016.
//

#import "Random.h"

#define ARC4RANDOM_MAX 0x100000000

@implementation Random {

}
+ (double)randomDoubleBetween:(double)low and:(double)high {
    return ((double) arc4random() / ARC4RANDOM_MAX)
            * (high - low)
            + low;
}
@end