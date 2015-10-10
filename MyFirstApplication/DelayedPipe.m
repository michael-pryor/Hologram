//
// Created by Michael Pryor on 10/10/2015.
//

#import "DelayedPipe.h"
#import "BlockingQueue.h"
#import "Timer.h"

@interface DelayedItem : NSObject
@property(readonly) id item;

- (Boolean)isItemReady;
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

- (Boolean)isItemReady {
    return [_timer getState];
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
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    DelayedItem *item = [[DelayedItem alloc] initWithItem:packet minimumDelay:_delay];
    [_delayedItems add:item];

    while (true) {
        DelayedItem *delayedItem = [_delayedItems getImmediate];
        if ([delayedItem isItemReady]) {
            [_outputSession onNewPacket:[delayedItem item] fromProtocol:protocol];
        } else {
            break;
        }
    }
}

- (void)reset {
    [_delayedItems clear];
}

@end