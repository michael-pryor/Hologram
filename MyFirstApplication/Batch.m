//
//  BatcherInputBatch.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import "Batch.h"

@implementation Batch {
    uint _chunksReceived;
    float _numChunksThreshold;

    uint _totalChunks;
    uint _lastChunkSize;
    bool _partialPacketUsedSizeFinalized;

    double _timeoutSeconds;
    ByteBuffer *_partialPacket;
    NSTimer *_timer;
    Boolean _hasOutput;
    id <BatchPerformanceInformation> _performanceDelegate;
    uint _batchId;
}

- (void)onTimeout:(NSTimer *)timer {
    //NSLog(@"Timed out with chunks received: %ul and threshold: %ul", _chunksReceived, _numChunksThreshold);
    if (_totalChunks == 0 || !_partialPacketUsedSizeFinalized) { // value not loaded yet.
        return;
    }

    uint integerNumChunksThreshold = (uint)(_numChunksThreshold * (float) _totalChunks);

    float chunksReceivedPercentage = ((float) _chunksReceived) / ((float) _totalChunks);
    [_performanceDelegate onNewPerformanceNotification:chunksReceivedPercentage];

    @synchronized (_partialPacket) {
        if (_chunksReceived >= integerNumChunksThreshold) {
            if (!_hasOutput) {
                [_partialPacket setCursorPosition:0];
                [_outputSession onNewPacket:_partialPacket fromProtocol:UDP];
                _hasOutput = true;
              //  NSLog(@"Output video batch ID: %d", _batchId);
            }
        } else {
            NSLog(@"Dropping video frame, percentage %.2f", chunksReceivedPercentage);
        }
    }
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession numChunksThreshold:(float)numChunksThreshold timeoutSeconds:(double)timeoutSeconds performanceInformationDelegate:(id <BatchPerformanceInformation>)performanceInformationDelegate batchId:(uint)batchId {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _chunksReceived = 0;
        _numChunksThreshold = numChunksThreshold;

        // Allocate some memory to prevent lots of resizing.
        _partialPacket = [[ByteBuffer alloc] initWithSize:1024 * 20];
        _partialPacketUsedSizeFinalized = false;

        _timeoutSeconds = timeoutSeconds;
        _hasOutput = false;
        _performanceDelegate = performanceInformationDelegate;
        _batchId = batchId;

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:_timeoutSeconds target:self selector:@selector(onTimeout:) userInfo:nil repeats:NO];
        });
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = [packet getUnsignedInteger];

    // Total chunks may be unknown, in which case each chunk also contains
    // a total chunks field.
    if (_totalChunks == 0) {
        _totalChunks = [packet getUnsignedInteger]; // use total chunks field.
    } else {
        [packet getUnsignedInteger]; // discard total chunks field.
    }

    if (_lastChunkSize == 0) {
        _lastChunkSize = [packet getUnsignedInteger];
    } else {
        [packet getUnsignedInteger];
    }

    uint chunkSize = [packet getUnreadDataFromCursor];
    uint buffPosition = chunkId * chunkSize;

    if (!_partialPacketUsedSizeFinalized && _lastChunkSize != 0 && _totalChunks != 0) {
        // Last chunk can be smaller, invalidating chunkSize.
        bool isLastChunkId = (_totalChunks - 1) == chunkId;
        if (!isLastChunkId) {
            uint partialPacketSize = ((_totalChunks - 1) * chunkSize) + _lastChunkSize;
            [_partialPacket setUsedSize:partialPacketSize];
            _partialPacketUsedSizeFinalized = true;
        }
    }

    // Copy contents of chunk packet into partial packet.
    Boolean fireNow = false; // optimization to avoid locking when timer fires.
    @synchronized (_partialPacket) {
        if (!_hasOutput) {
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

@end
