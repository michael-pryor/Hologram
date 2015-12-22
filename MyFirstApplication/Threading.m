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