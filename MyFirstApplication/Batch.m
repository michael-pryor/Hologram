//
//  BatcherInputBatch.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import "Batch.h"
#import "Timer.h"

@implementation Batch {
    uint _lastChunkSize;
    uint _normalChunkSize;

    Timer *_timeout;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession batchId:(uint)batchId timeoutSeconds:(CFAbsoluteTime)timeoutSeconds {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _chunksReceived = 0;

        _timeout = [[Timer alloc] initWithFrequencySeconds:timeoutSeconds firingInitially:false];

        // Allocate some memory to prevent lots of resizing.
        _partialPacket = [[ByteBuffer alloc] initWithSize:1024 * 20];
        _partialPacketUsedSizeFinalized = false;

        _batchId = batchId;
        _normalChunkSize = 0;

        _isComplete = false;
    }
    return self;
}

- (void)blockUntilTimeout {
    [_timeout blockUntilNextTick];
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
        _lastChunkSize = [packet getUnsignedInteger16];
    } else {
        [packet getUnsignedInteger16];
    }

    // Size of normal chunks; we need to cache it so that we don't use last chunk
    // in calculations.
    if (_normalChunkSize == 0) {
        // We don't know where to store the last chunk yet,
        // so all we can do is drop the data :(
        if (chunkId == _totalChunks - 1) {
            // NSLog(@"Failed to process chunk, received last chunk prior to other chunks");
            return;
        }

        _normalChunkSize = [packet getUnreadDataFromCursor];
    }
    uint buffPosition = chunkId * _normalChunkSize;

    @synchronized (_partialPacket) {
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
        [_partialPacket addByteBuffer:packet includingPrefix:false atPosition:buffPosition startingFrom:[packet cursorPosition]];

        _chunksReceived += 1;
        if (_chunksReceived == _totalChunks) {
            _isComplete = true;
        }
    }
}

@end
