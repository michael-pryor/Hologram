//
// Created by Michael Pryor on 10/10/2015.
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
#import "PipelineProcessor.h"

@interface DelayedPipe : PipelineProcessor
- (id)initWithMinimumDelay:(CFAbsoluteTime)delay outputSession:(id <NewPacketDelegate>)outputSession;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)reset;
@end