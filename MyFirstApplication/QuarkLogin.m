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

@implementation QuarkLogin {
    GpsState* _gpsState;
}
- (id)initWithGpsState:(GpsState*)gpsState {
    self = [super init];
    if(self) {
        _gpsState = gpsState;
    }
    return self;
}

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
        [buffer addUnsignedInteger:[_gpsState latitude]];
        [buffer addUnsignedInteger:[_gpsState longitude]];
    }
    
    return buffer;
}
@end
