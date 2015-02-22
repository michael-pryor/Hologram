//
//  BatcherInput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherInput.h"
#import "ByteBuffer.h"
#import "Batch.h"
@import Foundation;

@implementation BatcherInput {
    NSMutableDictionary* _batches;
    uint _chunkSize;
    uint _numChunks;
    uint _numChunksThreshold;
}
- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(uint)numChunksThreshold {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _batches = [[NSMutableDictionary alloc] init];
        _chunkSize = chunkSize;
        _numChunks = numChunks;
        _numChunksThreshold = numChunksThreshold;
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    uint batchId = [packet getUnsignedInteger];
    
    Batch* batch = [_batches objectForKey: [NSNumber numberWithInt:batchId]];
    if(batch == nil) {
        batch = [[Batch alloc] initWithOutputSession:_outputSession chunkSize:_chunkSize numChunks:_numChunks andNumChunksThreshold:_numChunksThreshold];
        [_batches setObject:batch forKey: [NSNumber numberWithInt:batchId]];
    }
    
    
}


@end
