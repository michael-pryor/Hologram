//
// Created by Michael Pryor on 22/12/2015.
//

#import "Threading.h"

void dispatch_sync_main(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

void dispatch_async_main(void (^block)(void), uint delayMs) {
    // Delay execution of my block for 10 seconds.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), block);
}