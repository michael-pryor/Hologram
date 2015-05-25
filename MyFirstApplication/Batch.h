//
//  BatcherInputBatch.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"

@protocol BatchPerformanceInformation
- (void)onNewOutput: (float)percentageFilled;
@end

@interface Batch : PipelineProcessor
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(float)numChunksThreshold andTimeoutSeconds:(double)timeoutSeconds andPerformanceInformaitonDelegate:(id<BatchPerformanceInformation>)performanceInformationDelegate;
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol;
@end
