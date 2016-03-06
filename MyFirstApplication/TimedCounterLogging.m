//
// Created by Michael Pryor on 06/03/2016.
//

#import "TimedCounterLogging.h"

#define DEFAULT_LOGGING_FREQ_SECONDS 60

@implementation TimedCounterLogging {
    NSString *_description;
}
- (id)initWithDescription:(NSString *)description timer:(Timer *)timer {
    self = [super initWithTimer:timer];
    if (self) {
        _description = description;
    }
    return self;
}

- (id)initWithDescription:(NSString *)description frequencySeconds:(CFAbsoluteTime)frequencySeconds {
    self = [super initWithFrequencySeconds:frequencySeconds];
    if (self) {
        _description = description;
    }
    return self;
}

- (id)initWithDescription:(NSString *)description {
    return [self initWithDescription:description frequencySeconds:DEFAULT_LOGGING_FREQ_SECONDS];
}

- (bool)incrementBy:(uint)increment {
    if ([super incrementBy:increment]) {
        NSLog(@"Counter [%@] has total of [%u] in last minute", _description, [self lastTotal]);
        return true;
    }

    return false;
}
@end