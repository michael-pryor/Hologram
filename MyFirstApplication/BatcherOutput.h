//
//  BatcherOutput.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "PipelineProcessor.h"
#import "ByteBuffer.h"

@protocol BatchNumberListener
- (void)onBatchNumberChange:(uint)newNumber;
@end

@interface BatcherOutput : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize leftPadding:(uint)leftPadding includeTotalChunks:(Boolean)includeTotalChunks batchNumberListener:(id <BatchNumberListener>)batchNumberListener;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;
@end