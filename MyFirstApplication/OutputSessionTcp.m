//
//  OutputSession.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import "OutputSessionTcp.h"
#import "BlockingQueue.h"

@implementation OutputSessionTcp {
    BlockingQueue *_queue;
    NSOutputStream *_outputStream;
    ByteBuffer *_sendBuffer;
    Boolean _sendViaThread;
}
- (id)init {
    self = [super init];
    if (self) {
        _queue = [[BlockingQueue alloc] init];
        _sendBuffer = [[ByteBuffer alloc] init];
        _sendViaThread = true;
    }
    return self;
}

- (void)restartSession {
    _sendViaThread = true;
    [_sendBuffer clear];
    [_queue restartQueue];
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (packet != nil) {
        ByteBuffer *prefixed;
        prefixed = [[ByteBuffer alloc] initWithSize:[packet bufferUsedSize] + sizeof(uint)];
        [prefixed addByteBuffer:packet includingPrefix:true];

        @synchronized (_queue) {
            [_queue add:prefixed];

            if (!_sendViaThread) {
                [self doSendOperation];
            }
        }
    } else {
        [_queue shutdown];
    }
}

- (void)loadOutputStream:(NSOutputStream *)stream {
    _outputStream = stream;
}

- (Boolean)doSendOperation {
    @synchronized (_queue) {
        if (_sendBuffer == nil || [_sendBuffer getUnreadDataFromCursor] == 0) {
            _sendBuffer = [self processPacket];

            // A nil packet indicates that there is nothing in the queue,
            // or that the output thread is being signaled for termination.
            if (_sendBuffer == nil) {
                _sendViaThread = false;
                return true;
            }

            [_sendBuffer setCursorPosition:0];
        }

        NSUInteger remaining = [_sendBuffer getUnreadDataFromCursor];
        uint8_t *buffer = [_sendBuffer buffer] + [_sendBuffer cursorPosition];

        if (remaining > 0) {
            NSUInteger bytesSent = [_outputStream write:buffer maxLength:remaining];
            if (bytesSent == -1) {
                return false;
            }
            [_sendBuffer moveCursorForwardsPassively:(uint) bytesSent];
            //NSLog(@"%lu TCP bytes sent, %lu remaining", (unsigned long) bytesSent, (unsigned long) [_sendBuffer getUnreadDataFromCursor]);
        }

        _sendViaThread = true;
        return true;
    }
}

- (ByteBuffer *)processPacket {
    return [_queue getImmediate];
}

@end
