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
    double _timeoutMs;
    double _batchRemovalTimeout;
}
- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(uint)numChunksThreshold andTimeoutMs:(uint)timeoutMs {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _batches = [[NSMutableDictionary alloc] init];
        _chunkSize = chunkSize;
        _numChunks = numChunks;
        _numChunksThreshold = numChunksThreshold;
        _timeoutMs = ((double)timeoutMs) / 1000;
        _batchRemovalTimeout = _timeoutMs * 3;
    }
    return self;
}

- (void)onTimeout:(NSNumber*)batchId {
    NSLog(@"Removing old batch, with ID: %@l", batchId);
    @synchronized(_batches) {
        [_batches removeObjectForKey:batchId];
    }
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    uint batchId = [packet getUnsignedInteger];
    
    Batch* batch;
    @synchronized(_batches) {
        batch = [_batches objectForKey: [NSNumber numberWithInt:batchId]];
        if(batch == nil) {
            batch = [[Batch alloc] initWithOutputSession:_outputSession chunkSize:_chunkSize numChunks:_numChunks andNumChunksThreshold:_numChunksThreshold andTimeoutSeconds:_timeoutMs];
            [_batches setObject:batch forKey: [NSNumber numberWithInt:batchId]];
            [NSTimer scheduledTimerWithTimeInterval:_batchRemovalTimeout target:self selector:@selector(onTimeout:) userInfo:[NSNumber numberWithInt: batchId]    repeats:NO];
        }
    }
    [batch onNewPacket:packet fromProtocol:protocol];
}


@end
