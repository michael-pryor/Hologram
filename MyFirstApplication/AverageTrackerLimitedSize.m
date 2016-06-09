//
// Created by Michael Pryor on 17/11/2015.
//

#import "AverageTrackerLimitedSize.h"

@implementation AverageTrackerLimitedSize {
    uint *_times;
    uint _total;
    uint _currentIndex;
    uint _timesSize;
    uint _numItems;
}

- (id)initWithMaxSize:(uint)sizeLimit {
    self = [super init];
    if (self) {
        _timesSize = sizeLimit;
        _times = malloc(sizeof(uint) * _timesSize);
        memset(_times, 0, sizeof(uint) * _timesSize);
        _total = 0;
        _numItems = 0;
    }
    return self;
}

- (void)dealloc {
    free(_times);
}

- (void)clear {
    @synchronized (self) {
        memset(_times, 0, sizeof(uint) * _timesSize);
        _total = 0;
        _numItems = 0;
    }
}

- (void)addValue:(uint)value {
    @synchronized (self) {
        if (_currentIndex >= _timesSize) {
            _currentIndex = 0;
            NSLog(@"Wrapped around");
        }

        _total -= _times[_currentIndex];
        _times[_currentIndex] = value;
        _total += value;

        _currentIndex++;
        if (_numItems < _timesSize) {
            _numItems++;
        }
    }

}

- (double)getWeightedAverage {
    @synchronized (self) {
        if (_numItems == 0) {
            return 0;
        }

        return (double) _total / (double) _numItems;
    }
}

@end