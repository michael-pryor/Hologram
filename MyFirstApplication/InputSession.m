//
//  InputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "InputSession.h"

@implementation BufferedPrefixInputSession
@synthesize buffer;
@synthesize bufferSize;

- (id) init: (int) p_bufferSize {
    self = [super init];
    if(self) {
        bufferSize = p_bufferSize;
    }
    return self;
}

- (void) onRecvData: (NSInteger)bytesReadIntoBuffer {
    
}

@end
