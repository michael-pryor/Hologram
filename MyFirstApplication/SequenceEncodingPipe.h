//
// Created by Michael Pryor on 09/03/2016.
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"

@interface SequenceEncodingPipe : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;
@end