//
//  BatcherOutput.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"
#import "ByteBuffer.h"

@interface BatcherOutput : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;
@end