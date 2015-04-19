//
//  BatcherInput.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"

@interface BatcherInput : PipelineProcessor
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(float)numChunksThreshold andTimeoutMs:(uint)timeoutMs;
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end