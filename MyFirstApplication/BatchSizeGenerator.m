//
// Created by Michael Pryor on 21/01/2016.
//

#import "BatchSizeGenerator.h"


@implementation BatchSizeGenerator {
    uint _minimumBatchSizeThreshold;
    uint _maximumBatchSizeThreshold;
    uint _maximumPacketSize;

    // Mapping from packet size (index in array) to batch size (value in array).
    uint *_batchSizeMappings;
    uint *_lastBatchSize;
}
- (id)initWithDesiredBatchSize:(uint)desiredBatchSize minimum:(uint)minimumBatchSizeThreshold maximum:(uint)maximiumBatchSizeThreshold maximumPacketSize:(uint)maximumPacketSize {
    self = [super init];
    if (self) {
        _desiredBatchSize = desiredBatchSize;
        _minimumBatchSizeThreshold = minimumBatchSizeThreshold;
        _maximumBatchSizeThreshold = maximiumBatchSizeThreshold;
        _maximumPacketSize = maximumPacketSize;

        _batchSizeMappings = malloc(sizeof(uint) * _maximumPacketSize);
        _lastBatchSize = malloc(sizeof(uint) * _maximumPacketSize);

        NSLog(@"Computing batch sizes...");
        for (uint n = 0; n < _maximumPacketSize; n++) {
            _batchSizeMappings[n] = [self computeBatchSizeFromPacketSize:n lastBatchSizes:_lastBatchSize + n];
        }
        NSLog(@"Finished computing batch sizes");

        // Disable below line in production code.
        [self verifyBatchSizesForDebugging];
    }
    return self;
}

- (uint)computeBatchSizeFromPacketSize:(uint)packetSize lastBatchSizes:(uint*)lastBatchSizes {
    // Outside our range, just return the most desired and don't worry about remainder,
    // there's nothing we can do.
    if (packetSize >= _maximumPacketSize) {
        if (lastBatchSizes != nil) {
            *lastBatchSizes = packetSize % _desiredBatchSize;
        }
        return _desiredBatchSize;
    }

    // Packet is too small to batch, so send as is.
    if (packetSize <= _desiredBatchSize) {
        if (lastBatchSizes != nil) {
            *lastBatchSizes = 0;
        }
        return packetSize;
    }

    uint up = _desiredBatchSize + 1;
    uint down = _desiredBatchSize - 1;

    uint lowestWaste = UINT32_MAX;
    uint lowestWasteBatchSize = _desiredBatchSize;

    while (true) {
        bool upHitThreshold = up == _maximumBatchSizeThreshold;
        bool downHitThreshold = down == _minimumBatchSizeThreshold;

        // Failed to get the optimum, return the best we have.
        if (upHitThreshold && downHitThreshold) {
            if (lastBatchSizes != nil) {
                *lastBatchSizes = lowestWasteBatchSize - lowestWaste;
            }
            return lowestWasteBatchSize;
        }

        if (!upHitThreshold) {
            uint remainder = packetSize % up;
            if (remainder == 0) {
                if (lastBatchSizes != nil) {
                    *lastBatchSizes = 0;
                }
                return up;
            }

            uint wasted = up - remainder;
            if (wasted < lowestWaste) {
                lowestWaste = wasted;
                lowestWasteBatchSize = up;
            }

            up++;
        }

        if (!downHitThreshold) {
            uint remainder = packetSize % down;
            if (remainder == 0) {
                if (lastBatchSizes != nil) {
                    *lastBatchSizes = 0;
                }
                return down;
            }

            uint wasted = down - remainder;
            if (wasted < lowestWaste) {
                lowestWaste = wasted;
                lowestWasteBatchSize = down;
            }

            down--;
        }
    }
}

- (void)dealloc {
    free(_batchSizeMappings);
    free(_lastBatchSize);
}

- (uint)getBatchSize:(uint)packetSize {
    if (packetSize >= _maximumPacketSize) {
        return _desiredBatchSize;
    }
    return _batchSizeMappings[packetSize];
}

- (uint)getLastBatchSize:(uint)packetSize {
    // Manually calculate since is outside of our range.
    if (packetSize >= _maximumPacketSize) {
        return packetSize % _desiredBatchSize;
    }
    return _lastBatchSize[packetSize];
}

- (void)verifyBatchSizesForDebugging {
    for (uint n = 0; n < _maximumPacketSize; n++) {
        uint batchSize = [self getBatchSize:n];
        if (n < _desiredBatchSize) {
            if (n != batchSize) {
                NSLog(@"Problem with small: %d", n);
            }

            continue;
        }

        uint remainder = n % batchSize;
        if (_lastBatchSize[n] != remainder) {
            NSLog(@"Serious problem, last batch size not marked properly");
        }

        if (remainder != 0) {
            NSLog(@"Imperfection with packet_size=%d, batch_size=%d, remainder=%d", n, batchSize, remainder);
        }
    }
}
@end