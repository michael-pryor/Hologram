//
// Created by Michael Pryor on 17/11/2015.
//

#import "AverageTrackerLimitedSize.h"
#import "Timer.h"
#import "BlockingQueue.h"

@implementation AverageTrackerLimitedSize {
    BlockingQueue *_blockingQueue;
    uint * times;
    uint _total;
    uint _currentIndex;
    uint _timesSize;
    uint _numItems;
}

- (id)initWithMaxSize:(uint)sizeLimit {
    self = [super init];
    if (self) {
        times = malloc(sizeof(uint) * sizeLimit);
        _timesSize = sizeLimit;
        _numItems = 0;
        memset(times, 0, sizeof(uint) * sizeLimit);
    }
    return self;
}

- (void)addValue:(uint)value {
    @synchronized (self) {
        if (_currentIndex >= _timesSize) {
            _currentIndex = 0;
        }

        _total -= times[_currentIndex];
        times[_currentIndex] = value;
        _total += value;

        _currentIndex++;
        if (_numItems < _timesSize) {
            _numItems++;
        }
    }

}

- (double)getWeightedAverage {
    @synchronized (self) {
        return (double)_total / (double)_numItems;
    }
}

@end