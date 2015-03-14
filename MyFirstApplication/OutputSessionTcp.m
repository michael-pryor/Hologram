//
//  OutputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "OutputSessionTcp.h"
#import <Foundation/Foundation.h>
#import "BlockingQueue.h"

@implementation OutputSessionTcp {
    BlockingQueue* _queue;
}
- (id) init {
    self = [super init];
    if(self) {
	    _queue = [[BlockingQueue alloc] init];
    }
    return self;
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if(packet != nil) {
        ByteBuffer* prefixed;
        prefixed = [[ByteBuffer alloc] initWithSize:[packet bufferUsedSize] + sizeof(uint)];
        [prefixed addByteBuffer:packet includingPrefix:true];
        [_queue add: prefixed];
    } else {
        [_queue shutdown];
    }
}

- (ByteBuffer*) processPacket {
    return [_queue get];
}

@end
