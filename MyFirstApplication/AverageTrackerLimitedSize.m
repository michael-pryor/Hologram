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

- (uint)decrement:(uint)index {
    if (index == 0) {
        return _timesSize - 1;
    }
    return index - 1;
}

- (double)getWeightedAverage {
    @synchronized (self) {
        if (_numItems == 0) {
            return 0;
        }

        return (double) _total / (double) _numItems;
    }
}

- (double)getStandardDeviation {
    @synchronized(self) {
        if (_numItems == 0) {
            return 0;
        }

        double average = [self getWeightedAverage];
        uint i = _currentIndex;
        uint totalIndex = _numItems;
        uint n = 0;
        double * deviations = malloc(sizeof(double)*_numItems);
        @try {
            while (totalIndex > 0) {
                i = [self decrement:i];

                double time = _times[i];
                double diff = time - average;
                deviations[n] = diff * diff;

                totalIndex--;
                n++;
            }

            double totalDeviations = 0;
            for (n = 0;n<_numItems;n++) {
                totalDeviations += deviations[n];
            }
            return sqrt(totalDeviations / _numItems);
        } @finally {
            free(deviations);
        }
    }
}

@end