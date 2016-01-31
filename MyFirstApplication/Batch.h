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
@property(readonly) Signal *hasOutput;
@property(readonly) uint batchId;
@property uint totalChunks;
@property bool partialPacketUsedSizeFinalized;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession timeoutSeconds:(double)timeoutSeconds batchId:(uint)batchId completionSelectorTarget:(id)aSelectorTarget completionSelector:(SEL)aSelector;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)reset;
@end
