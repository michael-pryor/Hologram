//
//  HologramLogin.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/07/2015.
//
//

#import "HologramLogin.h"
#import "SocialState.h"

@implementation HologramLogin {
    GpsState *_gpsState;
}
- (id)initWithGpsState:(GpsState *)gpsState {
    self = [super init];
    if (self) {
        _gpsState = gpsState;
    }
    return self;
}

- (ByteBuffer *)getLoginBuffer {
    ByteBuffer *buffer = [[ByteBuffer alloc] init];
    {
        SocialState *state = [SocialState getFacebookInstance];
        [buffer addString:[state humanFullName]];
        [buffer addString:[state humanShortName]];
        [buffer addUnsignedInteger:[state age]];
        [buffer addUnsignedInteger:[state genderI]];
        [buffer addUnsignedInteger:[state interestedIn]];
    }

    {
        [buffer addFloat:[_gpsState latitude]];
        [buffer addFloat:[_gpsState longitude]];
    }

    return buffer;
}
@end
