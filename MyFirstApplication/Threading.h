//
// Created by Michael Pryor on 22/12/2015.
//

// Dispatch to main thread and block.
void dispatch_sync_main(void (^block)(void));

void dispatch_async_main(void (^block)(void), uint delayMs);