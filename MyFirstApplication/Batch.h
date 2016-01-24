//
//  BatcherInputBatch.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"
#import "Signal.h"

@protocol BatchPerformanceInformation
- (void)onNewPerformanceNotification:(float)percentageFilled;
@end

@interface Batch : PipelineProcessor
@property uint chunksReceived;
@property(readonly) float numChunksThreshold;
@property(readonly) ByteBuffer *partialPacket;
@property(readonly) id <BatchPerformanceInformation> performanceDelegate;
@property(readonly) Signal *hasOutput;
@property(readonly) uint batchId;
@property uint totalChunks;
@property bool partialPacketUsedSizeFinalized;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession numChunksThreshold:(float)numChunksThreshold timeoutSeconds:(double)timeoutSeconds performanceInformationDelegate:(id <BatchPerformanceInformation>)performanceInformationDelegate batchId:(uint)batchId completionSelectorTarget:(id)aSelectorTarget completionSelector:(SEL)aSelector;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)reset;
@end
