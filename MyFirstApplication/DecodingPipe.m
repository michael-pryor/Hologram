//
//  DecodingPipe.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 21/03/2015.
//
//

#import "DecodingPipe.h"

@implementation DecodingPipe {
    NSMutableDictionary *map;
}
- (id)init {
    self = [super init];
    if (self) {
        map = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)addPrefix:(uint)prefix mappingToOutputSession:(id <NewPacketDelegate>)outputSession {
    [map setObject:outputSession forKey:[NSNumber numberWithUnsignedInt:prefix]];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    [packet setCursorPosition:0];
    uint prefix = [packet getUnsignedInteger];

    NSObject <NewPacketDelegate> *delegate = [map objectForKey:[NSNumber numberWithUnsignedInt:prefix]];
    if (delegate == nil) {
        NSLog(@"Unhandled packet received, invalid prefix: %ud", prefix);
        return;
    }

    [delegate onNewPacket:packet fromProtocol:protocol];
}
@end
