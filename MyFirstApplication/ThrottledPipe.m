//
//  ThrottledPipe.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "ThrottledPipe.h"
#import "ThrottledBlock.h"

@implementation ThrottledPipe {
    ThrottledBlock* _throttle;
}
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession defaultOutputFrequency:(CFAbsoluteTime)defaultOutputFrequency {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _throttle = [[ThrottledBlock alloc] initWithDefaultOutputFrequency:defaultOutputFrequency firingInitially:true];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    [_throttle runBlock:^ {
        [_outputSession onNewPacket:packet fromProtocol:protocol];
    }];
}

- (void)reset {
    [_throttle reset];
}

- (void)slowRate {
    [_throttle slowRate];
}
@end
