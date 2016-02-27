//
//  BatcherInput.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"
#import "Batch.h"

@interface BatcherInput : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession timeoutMs:(uint)timeoutMs;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)reset;

- (void)initialize;

- (void)terminate;
@end