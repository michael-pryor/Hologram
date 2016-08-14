//
//  BatcherInput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherInput.h"
#import "BlockingQueue.h"

@implementation BatcherInput {
    // Dictionary from batch ID to batch.
    NSMutableDictionary *_batches;
    uint _greatestCompletedBatchId; // synchronized with _batches lock.

    // Queue which dedicated thread reads on and discards/processes batches
    // as they time out. Timing out means we give up waiting for future
    // chunks to arrive, which may make the batch complete.
    BlockingQueue *_batchesTimeout;
    CFAbsoluteTime _timeoutSeconds;

    NSThread *_timeoutThread;
    bool _isRunning;
}
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession timeoutMs:(uint)timeoutMs {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _batches = [[NSMutableDictionary alloc] init];
        _batchesTimeout = [[BlockingQueue alloc] init];
        _timeoutSeconds = ((double) timeoutMs) / 1000;
        _greatestCompletedBatchId = 0;
        _isRunning = false;
    }
    return self;
}

- (void)initialize {
    _isRunning = true;
    _timeoutThread = [[NSThread alloc] initWithTarget:self
                                             selector:@selector(timeoutThreadEntryPoint:)
                                               object:nil];
    [_timeoutThread setName:@"BatcherInput Timeout"];
    [_timeoutThread start];
}

- (void)terminate {
    _isRunning = false;
    [_batchesTimeout shutdown];
}

- (void)timeoutThreadEntryPoint:var {
    while (_isRunning) {
        @autoreleasepool {
            Batch *batch = [_batchesTimeout get];
            if (batch == nil) {
                break;
            }

            [batch blockUntilTimeout];

            // If has already been processed (e.g. because it became complete) then will
            // not process again. Checks are inside this call.
            [self onBatchCompletion:batch timedOut:true];
        }
    }

    NSLog(@"BatcherInput thread terminating");
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (!_isRunning) {
        NSLog(@"BatcherInput not running, dropping new packet");
        return;
    }

    // Note: do not change the format of the batch ID (it must be a 16 bit unsigned integer), because
    // this data is inspected for packet loss by a SequenceDecodingPipe, prior to hitting this point.
    uint batchId = [packet getUnsignedInteger16];

    Batch *batch;
    @synchronized (_batches) {
        batch = _batches[@(batchId)];
        if (batch == nil) {
            batch = [[Batch alloc] initWithOutputSession:_outputSession batchId:batchId timeoutSeconds:_timeoutSeconds];
            _batches[@(batchId)] = batch;
            [_batchesTimeout add:batch];
        }
    }

    [batch onNewPacket:packet fromProtocol:protocol];
    if ([batch isComplete]) {
        [self onBatchCompletion:batch timedOut:false];
    }
}

- (void)reset {
    @synchronized (_batches) {
        // Remove all batches from memory.
        [_batches removeAllObjects];

        // Reset the greatest count.
        _greatestCompletedBatchId = 0;
    }
}

- (void)discardBatch:(Batch *)batch {
    @synchronized (_batches) {
        [_batches removeObjectForKey:@([batch batchId])];
    }
}

- (void)onBatchCompletion:(Batch *)batch timedOut:(bool)isTimedOut {
    if (!_isRunning) {
        NSLog(@"Dropping completed batch because BatcherInput is not running");
        return;
    }

    uint batchId = [batch batchId];

    @synchronized ([batch partialPacket]) {
        @synchronized (_batches) {
            if (_batches[@([batch batchId])] == nil) {
                // Already processed.
                return;
            }

            if (![batch isComplete]) {
                NSLog(@"Dropping incomplete video frame with batch ID: %d", batchId);
                [self discardBatch:batch];
                return;
            }

            if (batchId > _greatestCompletedBatchId) {
                _greatestCompletedBatchId = batchId;
            } else if (batchId < _greatestCompletedBatchId) {

                // Tolerate integer overflow.
                int difference = _greatestCompletedBatchId - batchId;

                // Arbitrary value here..
                // If something goes wrong and our _greatestCompletedBatchId, the worst case will be some delay in video,
                // rather than permanent video failure.
                //
                // If it timed out, then it naturally had some delay in it, we should therefore not bother with
                // overflow for this. We don't do true overflow, we have an arbitrary number, so that's why it's important.
                if (difference > 500 && !isTimedOut) {
                    NSLog(@"Integer overflow detected with batch ID: %d vs greatest %d, resetting greatest to 0", batchId, _greatestCompletedBatchId);
                    _greatestCompletedBatchId = 0;
                } else {
                    // Common place for timed out batches, since they will often already have been processed.
                    if (!isTimedOut) {
                        NSLog(@"Dropping old batch %d vs %d", batchId, _greatestCompletedBatchId);
                    }
                    [self discardBatch:batch];
                    return;
                }
            }

            // We want to remove from batches store prior to processing it.
            [self discardBatch:batch];
        }

        // Process the batch.
        // Must be within partial packet synchronization, because we don't copy the buffer,
        // we use it directly.
        //
        // If another chunk comes in, it won't be added to the buffer until we're done processing it.
        // The buffer will then be deallocated since there will be no references to it.
        [[batch partialPacket] setCursorPosition:0];
        [_outputSession onNewPacket:[batch partialPacket] fromProtocol:UDP];
    }
}

- (void)dealloc {
    [self terminate];
    NSLog(@"BatcherInput dealloc");
}
@end
