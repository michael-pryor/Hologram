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

@interface Batch : PipelineProcessor
@property uint chunksReceived;
@property(readonly) ByteBuffer *partialPacket;
@property(readonly) uint batchId;
@property uint totalChunks;
@property bool partialPacketUsedSizeFinalized;
@property(readonly) bool isComplete;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession batchId:(uint)batchId timeoutSeconds:(CFAbsoluteTime)timeoutSeconds;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)blockUntilTimeout;
@end
