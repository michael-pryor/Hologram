//
//  BatcherInput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherInput.h"

@implementation BatcherInput {
    NSMutableDictionary *_batches;
    uint _chunkSize;
    uint _numChunks;
    float _numChunksThreshold;
    double _timeoutMs;
    double _batchRemovalTimeout;
    id <BatchPerformanceInformation> _performanceDelegate;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(float)numChunksThreshold andTimeoutMs:(uint)timeoutMs andPerformanceInformaitonDelegate:(id <BatchPerformanceInformation>)performanceInformationDelegate {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _batches = [[NSMutableDictionary alloc] init];
        _chunkSize = chunkSize;
        _numChunks = numChunks;
        _numChunksThreshold = numChunksThreshold;
        _timeoutMs = ((double) timeoutMs) / 1000;
        _batchRemovalTimeout = _timeoutMs * 3;
        _performanceDelegate = performanceInformationDelegate;
    }
    return self;
}

- (void)onTimeout:(NSTimer *)timer {
    NSNumber *batchId = [timer userInfo];
    //NSLog(@"Removing old batch, with ID: %@l", batchId);
    @synchronized (_batches) {
        [_batches removeObjectForKey:batchId];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint batchId = [packet getUnsignedInteger];

    Batch *batch;
    @synchronized (_batches) {
        batch = [_batches objectForKey:[NSNumber numberWithInt:batchId]];
        if (batch == nil) {
            batch = [[Batch alloc] initWithOutputSession:_outputSession chunkSize:_chunkSize numChunks:_numChunks andNumChunksThreshold:_numChunksThreshold andTimeoutSeconds:_timeoutMs andPerformanceInformaitonDelegate:_performanceDelegate andBatchId:batchId];
            [_batches setObject:batch forKey:[NSNumber numberWithInt:batchId]];

            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [NSTimer scheduledTimerWithTimeInterval:_batchRemovalTimeout target:self selector:@selector(onTimeout:) userInfo:[NSNumber numberWithInt:batchId] repeats:NO];
            });
        }
    }
    [batch onNewPacket:packet fromProtocol:protocol];
}


@end
