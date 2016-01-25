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
    uint _greatestCompletedBatchId;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession numChunksThreshold:(float)numChunksThreshold timeoutMs:(uint)timeoutMs {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _batches = [[NSMutableDictionary alloc] init];
        _numChunksThreshold = numChunksThreshold;
        _timeoutMs = ((double) timeoutMs) / 1000;
        _greatestCompletedBatchId = 0;
    }
    return self;
}

- (void)onTimeoutB:(NSTimer *)timer {
    NSNumber *batchId = [timer userInfo];
    //NSLog(@"Removing old batch, with ID: %@l", batchId);
    @synchronized (_batches) {
        [_batches removeObjectForKey:batchId];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint batchId = [packet getUnsignedInteger16];

    Batch *batch;
    @synchronized (_batches) {
        batch = _batches[@(batchId)];
        if (batch == nil) {
            batch = [[Batch alloc] initWithOutputSession:_outputSession timeoutSeconds:_timeoutMs batchId:batchId completionSelectorTarget:self completionSelector:@selector(onBatchTimeout:)];
            _batches[@(batchId)] = batch;
        }
    }
    [batch onNewPacket:packet fromProtocol:protocol];
}

- (void)reset {
    @synchronized (_batches) {
        // Prevent batches from firing (calling onBatchTimeout).
        for (id key in _batches) {
            Batch *value = _batches[key];
            [value reset];
        }

        // Remove all batches from memory.
        [_batches removeAllObjects];

        // Reset the greatest count.
        _greatestCompletedBatchId = 0;
    }
}

- (void)onBatchTimeout:(NSTimer *)timer {
    Batch *batch = [timer userInfo];
    uint batchId = [batch batchId];

    if ([batch totalChunks] == 0 || ![batch partialPacketUsedSizeFinalized]) { // value not loaded yet.
        NSLog(@"Dropping very incomplete video frame with batch ID: %d", batchId);
        @synchronized (_batches) {
            [_batches removeObjectForKey:@([batch batchId])];
        }
        return;
    }

    uint integerNumChunksThreshold = (uint) (_numChunksThreshold * (float) [batch totalChunks]);

    float chunksReceivedPercentage = ((float) [batch chunksReceived]) / ((float) [batch totalChunks]);

    @synchronized ([batch partialPacket]) {
        if ([batch chunksReceived] >= integerNumChunksThreshold) {
            if ([[batch hasOutput] signal]) {
                [[batch partialPacket] setCursorPosition:0];

                @synchronized (_batches) {
                    [_batches removeObjectForKey:@([batch batchId])];

                    if (batchId > _greatestCompletedBatchId) {
                        _greatestCompletedBatchId = batchId;
                    } else if (batchId < _greatestCompletedBatchId) {

                        // Tolerate integer overflow.
                        int difference = _greatestCompletedBatchId - batchId;
                        if (difference > (UINT16_MAX / 2)) {
                            NSLog(@"Integer overflow detected with batch ID: %d vs greatest %d, resetting greatest to 0", batchId, _greatestCompletedBatchId);
                            _greatestCompletedBatchId = 0;
                        } else {
                            NSLog(@"Dropping old batch %d vs %d", batchId, _greatestCompletedBatchId);
                            return;
                        }
                    }
                }

                [_outputSession onNewPacket:[batch partialPacket] fromProtocol:UDP];
                //NSLog(@"Joiner, completed batch ID: %d", [batch batchId]);
            }
        } else {
            NSLog(@"Dropping video frame, percentage %.2f and batch ID: %d", chunksReceivedPercentage, batchId);
            @synchronized (_batches) {
                [_batches removeObjectForKey:@([batch batchId])];
            }
        }
    }
}
@end
