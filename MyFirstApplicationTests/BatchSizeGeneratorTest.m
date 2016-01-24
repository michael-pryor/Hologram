//
// Created by Michael Pryor on 24/01/2016.
//

#import <XCTest/XCTest.h>
#import "BatchSizeGenerator.h"


@interface BatchSizeGeneratorTest : XCTestCase
@end

@implementation BatchSizeGeneratorTest {

}

- (void)testValues {
    int maximumPacketSize = 12000;
    int desiredBatchSize = 128;
    BatchSizeGenerator *generator = [[BatchSizeGenerator alloc] initWithDesiredBatchSize:desiredBatchSize minimum:90 maximum:256 maximumPacketSize:maximumPacketSize];

    for (uint n = 0; n < maximumPacketSize+1000; n++) {
        uint batchSize = [generator getBatchSize:n];
        uint remainder = [generator getLastBatchSize:n];
        if (n < desiredBatchSize) {
            assert (n == batchSize);
            assert (remainder == 0);
            continue;
        }

        uint expectedRemainder = n % batchSize;
        assert (expectedRemainder == remainder);

        if (n % desiredBatchSize == 0) {
            assert(expectedRemainder == 0);
        }

        if (desiredBatchSize == batchSize && n < maximumPacketSize) {
            assert(n % desiredBatchSize == 0);
            assert(remainder == 0);
        }

        if (remainder != 0) {
            NSLog(@"Imperfection with packet_size=%d, batch_size=%d, remainder=%d", n, batchSize, remainder);
        }
    }
}
@end