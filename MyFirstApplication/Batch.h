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
- (void)onNewPerformanceNotification:(float)percentageFilled;
@end

@interface Batch : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession numChunksThreshold:(float)numChunksThreshold timeoutSeconds:(double)timeoutSeconds performanceInformationDelegate:(id <BatchPerformanceInformation>)performanceInformationDelegate batchId:(uint)batchId;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;
@end
