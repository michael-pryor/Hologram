//
//  HologramLogin.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/07/2015.
//
//

#import "HologramLogin.h"
#import "SocialState.h"
#import "UniqueId.h"

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
    SocialState *state = [SocialState getSocialInstance];
    {
        uint8_t isNewFlag;
        if([[UniqueId getUniqueIdInstance] isValidatedUUID]) {
            isNewFlag = 0;
        } else {
            isNewFlag = 1;
        }

        [buffer addUnsignedInteger8:isNewFlag];
        [buffer addString:[[UniqueId getUniqueIdInstance] getUUID]];
        [buffer addString:[state humanFullName]];
        [buffer addString:[state humanShortName]];
        [buffer addUnsignedInteger:[state age]];
        [buffer addUnsignedInteger:[state genderEnum]];
        [buffer addUnsignedInteger:[state interestedIn]];
    }

    {
        [buffer addFloat:[_gpsState latitude]];
        [buffer addFloat:[_gpsState longitude]];
        [buffer addData:_regenerateKarmaReceipt];
    }

    {
        [buffer addString:[state callingCardText]];
        [buffer addData:[state profilePictureData]];
        [buffer addUnsignedInteger:[state profilePictureOrientationInteger]];
    }

    return buffer;
}

- (void)clearKarmaRegeneration {
    _regenerateKarmaReceipt = nil;
}
@end
