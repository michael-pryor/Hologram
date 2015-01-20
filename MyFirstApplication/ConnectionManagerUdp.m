//
//  ConnectionManagerUdp.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import "ConnectionManagerUdp.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <dispatch/dispatch.h>

@implementation ConnectionManagerUdp {
    int _socObject;
    dispatch_queue_t _gcd_queue;
    dispatch_source_t _dispatch_source;
}

- (id) init {
    self = [super init];
    if(self) {
        _gcd_queue = dispatch_queue_create("ConnectionManagerUdp", NULL);
        _socObject = 0;
    }
    return self;
}

- (void) validateResult: (int)result {
    if(result < 0) {
        NSLog(@"UDP networking failure, reason %ul", errno);
    }
}

- (void) close {
    if([self isConnected]) {
        NSLog(@"Closing existing UDP socket");
        close(_socObject);
        _socObject = 0;
    }
}

- (void) shutdown {
    [self close];
}
- (Boolean) isConnected {
    return _socObject != 0;
}

- (void) onRecv {
    long maximumAmountReceivable = dispatch_source_get_data(_dispatch_source);
    size_t realAmountReceived;
    
    do {
        ByteBuffer* buffer = [[ByteBuffer alloc] init];
        [buffer setMemorySize:maximumAmountReceivable retaining:false];
        realAmountReceived = recv(_socObject, [buffer getRawDataPtr], maximumAmountReceivable, 0);
    
        // This would cause buffer overrun and indicates a serious bug somewhere (probably not in our code though *puts on sunglasses slowly*).
        if(realAmountReceived != maximumAmountReceivable) {
            NSLog(@"Receive error detected: %zu (real) vs %ld (maximum)", realAmountReceived, maximumAmountReceivable);
        }
        
        [buffer setUsedSize: realAmountReceived];
    
        NSLog(@"Received UDP packet of size: %ul", [buffer bufferUsedSize]);
        
        maximumAmountReceivable -= realAmountReceived;
    } while(maximumAmountReceivable > 0);
}

- (void) connectToHost: (NSString*) host andPort: (ushort) port {
    [self close];
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr([host UTF8String]);
    
    _socObject = socket(AF_INET, SOCK_DGRAM, 0);
    [self validateResult: connect(_socObject, (const struct sockaddr *)&addr, sizeof(addr))];
    
    _dispatch_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _socObject, 0, _gcd_queue);
    dispatch_source_set_event_handler(_dispatch_source, ^{
        [self onRecv];
    });
    dispatch_resume(_dispatch_source);
    NSLog(@"Connected UDP socket to host %@ and port %u", host, port);
}

- (void) sendPacket: (ByteBuffer*)buffer {
    long result = send(_socObject, [buffer buffer], [buffer bufferUsedSize], 0);
    if(result >= 0) {
        NSLog(@"Sent UDP packet with size: %ldl", result);
    } else {
        [self validateResult: -1];
    }
}
@end
