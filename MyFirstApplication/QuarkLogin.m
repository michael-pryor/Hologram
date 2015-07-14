//
//  QuarkLogin.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/07/2015.
//
//

#import "QuarkLogin.h"
#import "SocialState.h"
#import "GpsState.h"

@implementation QuarkLogin
- (ByteBuffer*)getLoginBuffer {
    ByteBuffer* buffer = [[ByteBuffer alloc] init];
    {
        SocialState* state = [SocialState getFacebookInstance];
        [buffer addString:[state humanFullName]];
        [buffer addString:[state humanShortName]];
        [buffer addUnsignedInteger:[state age]];
        [buffer addUnsignedInteger:[state genderI]];
        [buffer addUnsignedInteger:[state interestedInI]];
    }
    
    {
        GpsState* state = [GpsState getInstance];
        [buffer addUnsignedInteger:[state latitude]];
        [buffer addUnsignedInteger:[state longitude]];
    }
    
    return buffer;
}
@end
