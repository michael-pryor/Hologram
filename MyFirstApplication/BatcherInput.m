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
    float _numChunksThreshold;
    double _timeoutMs;
    double _batchRemovalTimeout;
    id <BatchPerformanceInformation> _performanceDelegate;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession numChunksThreshold:(float)numChunksThreshold timeoutMs:(uint)timeoutMs performanceInformationDelegate:(id <BatchPerformanceInformation>)performanceInformationDelegate {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _batches = [[NSMutableDictionary alloc] init];
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
            batch = [[Batch alloc] initWithOutputSession:_outputSession numChunksThreshold:_numChunksThreshold timeoutSeconds:_timeoutMs performanceInformationDelegate:_performanceDelegate batchId:batchId];
            [_batches setObject:batch forKey:[NSNumber numberWithInt:batchId]];

            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [NSTimer scheduledTimerWithTimeInterval:_batchRemovalTimeout target:self selector:@selector(onTimeout:) userInfo:[NSNumber numberWithInt:batchId] repeats:NO];
            });
        }
    }
    [batch onNewPacket:packet fromProtocol:protocol];
}


@end
