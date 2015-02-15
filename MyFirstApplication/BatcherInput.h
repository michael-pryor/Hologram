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
- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession andChunkSize:(uint)chunkSize;
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end