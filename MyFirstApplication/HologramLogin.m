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
    NSData *_regenerateKarmaReceipt;
}
- (id)initWithGpsState:(GpsState *)gpsState regenerateKarmaReceipt:(NSData *)receipt {
    self = [super init];
    if (self) {
        _gpsState = gpsState;
        _regenerateKarmaReceipt = receipt;
    }
    return self;
}

- (ByteBuffer *)getLoginBuffer {
    ByteBuffer *buffer = [[ByteBuffer alloc] init];
    {
        SocialState *state = [SocialState getFacebookInstance];
        [buffer addString:[state facebookId]];
        [buffer addString:[[state facebookUrl] absoluteString]];
        [buffer addString:[[state facebookProfilePictureUrl] absoluteString]];
        [buffer addString:[state humanFullName]];
        [buffer addString:[state humanShortName]];
        [buffer addUnsignedInteger:[state age]];
        [buffer addUnsignedInteger:[state genderI]];
        [buffer addUnsignedInteger:[state interestedIn]];
    }

    {
        [buffer addFloat:[_gpsState latitude]];
        [buffer addFloat:[_gpsState longitude]];
        [buffer addData:_regenerateKarmaReceipt];
    }

    return buffer;
}

- (void)clearKarmaRegeneration {
    _regenerateKarmaReceipt = nil;
}
@end
