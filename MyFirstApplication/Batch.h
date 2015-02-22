//
//  BatcherInputBatch.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"

@interface Batch : PipelineProcessor
- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(uint)numChunksThreshold;
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end
