//
// Created by Michael Pryor on 10/10/2015.
//

#import "DelayedPipe.h"
#import "BlockingQueue.h"
#import "Timer.h"

@interface DelayedItem : NSObject
@property id item;
@end

@implementation DelayedItem {
    Timer *_timer;
}
- (id)initWithItem:(id)item minimumDelay:(CFAbsoluteTime)delay {
    self = [super init];
    if (self) {
        _timer = [[Timer alloc] initWithFrequencySeconds:delay firingInitially:false];
        _item = item;
    }
    return self;
}

- (bool)isItemReadyMaxDelay:(CFAbsoluteTime)maxDelay {
    CFAbsoluteTime timerFrequency = [_timer secondsFrequency];
    CFAbsoluteTime frequencyToUse = timerFrequency < maxDelay ? timerFrequency : maxDelay;
    return [_timer getStateWithFrequencySeconds:frequencyToUse];
}
@end

@implementation DelayedPipe {
    BlockingQueue *_delayedItems;
    CFAbsoluteTime _delay;
}
- (id)initWithMinimumDelay:(CFAbsoluteTime)delay outputSession:(id <NewPacketDelegate>)outputSession {
    self = [super initWithOutputSession:outputSession];
    if (self) {
        _delay = delay;
        _delayedItems = [[BlockingQueue alloc] init];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    DelayedItem *item = [[DelayedItem alloc] initWithItem:packet minimumDelay:_delay];

    // Make a copy because the buffer needs to be kept past this call.
    // Buffer passed in may get reused.
    [item setItem:[[ByteBuffer alloc] initFromByteBuffer:packet]];
    [_delayedItems add:item];

    while (true) {
        DelayedItem *delayedItem = [_delayedItems peek];
        if (delayedItem == nil) {
            break;
        }
        
        if ([delayedItem isItemReadyMaxDelay:_delay]) {
            DelayedItem * retrievedItem = [_delayedItems getImmediate];
            if (retrievedItem != delayedItem) {
                continue;
            }
            [_outputSession onNewPacket:[retrievedItem item] fromProtocol:protocol];
        } else {
            break;
        }
    }
}

- (void)reset {
    [_delayedItems clear];
}

- (void)setMinimumDelay:(CFAbsoluteTime)delay {
    _delay = delay;
}

- (void)dealloc {
    NSLog(@"DelayedPipe dealloc");
}

@end