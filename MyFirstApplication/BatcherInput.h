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
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession numChunksThreshold:(float)numChunksThreshold timeoutMs:(uint)timeoutMs performanceInformationDelegate:(id <BatchPerformanceInformation>)performanceInformationDelegate;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)reset;
@end