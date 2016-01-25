//
//  BatcherInputBatch.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import "Batch.h"
#import "Threading.h"

@implementation Batch {
    uint _lastChunkSize;
    uint _normalChunkSize;

    NSTimer *_timer;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession timeoutSeconds:(double)timeoutSeconds batchId:(uint)batchId completionSelectorTarget:(id)aSelectorTarget completionSelector:(SEL)aSelector {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _chunksReceived = 0;

        // Allocate some memory to prevent lots of resizing.
        _partialPacket = [[ByteBuffer alloc] initWithSize:1024 * 20];
        _partialPacketUsedSizeFinalized = false;

        _hasOutput = [[Signal alloc] initWithFlag:false];
        _batchId = batchId;
        _normalChunkSize = 0;

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:timeoutSeconds target:aSelectorTarget selector:aSelector userInfo:self repeats:NO];
        });
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = [packet getUnsignedInteger16];

    // Total chunks may be unknown, in which case each chunk also contains
    // a total chunks field.
    if (_totalChunks == 0) {
        _totalChunks = [packet getUnsignedInteger16]; // use total chunks field.
    } else {
        [packet getUnsignedInteger16]; // discard total chunks field.
    }

    // Size of the last chunk in the batch (may be less than other chunks).
    if (_lastChunkSize == 0) {
        _lastChunkSize = [packet getUnsignedInteger8];
    } else {
        [packet getUnsignedInteger8];
    }

    // Size of normal chunks; we need to cache it so that we don't use last chunk
    // in calculations.
    if (_normalChunkSize == 0) {
        // We don't know where to store the last chunk yet,
        // so all we can do is drop the data :(
        if (chunkId == _totalChunks - 1) {
            NSLog(@"Failed to process chunk, received last chunk prior to other chunks");
            return;
        }

        _normalChunkSize = [packet getUnreadDataFromCursor];
    }
    uint buffPosition = chunkId * _normalChunkSize;

    if (!_partialPacketUsedSizeFinalized && _lastChunkSize != 0 && _totalChunks != 0 && _normalChunkSize != 0) {
        // Last chunk can be smaller, invalidating chunkSize.
        bool isLastChunkId = (_totalChunks - 1) == chunkId;
        if (!isLastChunkId) {
            uint partialPacketSize = ((_totalChunks - 1) * _normalChunkSize) + _lastChunkSize;
            [_partialPacket setUsedSize:partialPacketSize];
            _partialPacketUsedSizeFinalized = true;
        }
    }

    //NSLog(@"Joiner - generated chunk with batch ID: %d, chunkID: %d, num chunks: %d, last chunk size: %d, full batch size real: %d, current chunk size: %d, current full chunk packet size: %d, joined buff position: %d", _batchId, chunkId, _totalChunks, _lastChunkSize, [_partialPacket bufferUsedSize], [packet getUnreadDataFromCursor], [packet bufferUsedSize], buffPosition);

    // Copy contents of chunk packet into partial packet.
    bool fireNow = false; // optimization to avoid locking when timer fires.
    @synchronized (_partialPacket) {
        if (![_hasOutput isSignaled]) {
            [_partialPacket addByteBuffer:packet includingPrefix:false atPosition:buffPosition startingFrom:[packet cursorPosition]];

            _chunksReceived += 1;
            if (_chunksReceived == _totalChunks) {
                fireNow = true;
            }
        }
    }
    if (fireNow) {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [_timer fire];
        });
    }
}

- (void)reset {
    dispatch_sync_main(^(void) {
        [_timer invalidate];
    });
}

@end
