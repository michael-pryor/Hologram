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
    int _mainSocketObject;
    dispatch_queue_t _gcd_queue;
    dispatch_source_t _dispatch_source;
    id<NewPacketDelegate> _newPacketDelegate;
    ByteBuffer* _recvBuffer;
    ushort _port;
    int* _sockets;
    uint _currentSocket;
}

- (id) initWithNewPacketDelegate:(id<NewPacketDelegate>)newPacketDelegate andNumSockets:(uint)numSockets {
    self = [super init];
    if(self) {
        _gcd_queue = dispatch_queue_create("ConnectionManagerUdp", NULL);
        _mainSocketObject = 0;
        _newPacketDelegate = newPacketDelegate;
        _recvBuffer = [[ByteBuffer alloc] init];
        _port = 0;
        _mainSocketObject = 0;
        _numSockets = numSockets;
        _sockets = malloc(sizeof(int) * _numSockets);
        _currentSocket = 0;
    }
    return self;
}

- (void) dealloc {
    free(_sockets);
}

- (void) validateResult: (int)result {
    if(result < 0) {
        int err = errno;
        NSLog(@"UDP networking failure, reason %d", err);
        [self close];
    }
}

- (void) close {
    if([self isConnected]) {
        NSLog(@"Closing existing UDP socket");
        close(_mainSocketObject);
        _mainSocketObject = 0;
    }
}

- (void) shutdown {
    [self close];
}
- (Boolean) isConnected {
    return _mainSocketObject != 0;
}

- (void) onRecv {
    long maximumAmountReceivable = dispatch_source_get_data(_dispatch_source);
    size_t realAmountReceived;
    
    do {
        if(maximumAmountReceivable > [_recvBuffer bufferMemorySize]) {
            [_recvBuffer setMemorySize:(uint)maximumAmountReceivable retaining:false];
        }
        
        realAmountReceived = recv(_mainSocketObject, [_recvBuffer getRawDataPtr], maximumAmountReceivable, 0);
    
        // This would cause buffer overrun and indicates a serious bug somewhere (probably not in our code though *puts on sunglasses slowly*).
        if(realAmountReceived == -1) {
            NSLog(@"Serious receive error detected");
            [self validateResult:-1];
            return;
        }
        if(realAmountReceived > maximumAmountReceivable) {
            NSLog(@"Receive error detected: %zu (real) vs %ld (maximum)", realAmountReceived, maximumAmountReceivable);
        }
        
        [_recvBuffer setUsedSize: (uint)realAmountReceived];
    
        //NSLog(@"Received UDP packet of size: %ul", [_recvBuffer bufferUsedSize]);
        [_newPacketDelegate onNewPacket:_recvBuffer fromProtocol:UDP];
        
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
    
    for(int n = 0;n<_numSockets;n++) {
        int currentSocketObject = socket(AF_INET, SOCK_DGRAM, 0);
        if(_mainSocketObject == 0) {
            _mainSocketObject = currentSocketObject;
        }
        /*if(_port != 0) {
            struct sockaddr_in localAddr;
            memset(&localAddr, 0, sizeof(localAddr));
            
            addr.sin_family = AF_INET;
            addr.sin_port = htons(_port);
        
            [self validateResult: bind(currentSocketObject, (const struct sockaddr *)&localAddr, sizeof(localAddr))];
        }*/

        [self validateResult: connect(currentSocketObject, (const struct sockaddr *)&addr, sizeof(addr))];

        int optval = 1;
        setsockopt(currentSocketObject, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    
        if(_port == 0) {
            struct sockaddr_in sin;
            socklen_t len = sizeof(sin);
            [self validateResult: getsockname(currentSocketObject, (struct sockaddr *)&sin, &len)];
            _port = ntohs(sin.sin_port);
            NSLog(@"Bound to UDP port: %u", _port);
        }
        NSLog(@"Connected UDP socket to host %@ and port %u", host, port);
        _sockets[n] = currentSocketObject;
    }
    
    _dispatch_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _mainSocketObject, 0, _gcd_queue);
    dispatch_source_set_event_handler(_dispatch_source, ^{
        [self onRecv];
    });
    dispatch_resume(_dispatch_source);
}

- (void)onNewPacket:(ByteBuffer *)buffer fromProtocol:(ProtocolType)protocol {
    /*fd_set write;
    uint ready;
    do {
        FD_ZERO(&write);
        FD_SET(_socObject, &write);
        ready = select(FD_SETSIZE, nil, &write, nil, nil);
        if(ready == -1) {
            NSLog(@"Select error!!!");
        } else if(ready < 1 || !FD_ISSET(_socObject, &write)) {
            NSLog(@"Not ready yet!");
            [NSThread sleepForTimeInterval:0.01];
        }
    } while(ready < 1 || !FD_ISSET(_socObject, &write));*/

    [self sendBuffer:buffer];
}

- (void)sendBufferToAllSockets:(ByteBuffer*)buffer {
    for(int n = 0;n<_numSockets;n++) {
        [self sendBuffer:buffer toSocketWithId:n];
    }
}

- (void)sendBufferToPrimary:(ByteBuffer*)primary andToSecondary:(ByteBuffer*)secondary {
    for(int n = 0;n<_numSockets;n++) {
        int currentSocket = _sockets[n];
        if(currentSocket == _mainSocketObject) {
            [self sendBuffer:primary toSocketWithId:n];
        } else {
            [self sendBuffer:secondary toSocketWithId:n];
        }
    }
}

- (void)sendBuffer:(ByteBuffer*)buffer toSocketWithId:(uint)socketId {
    int currentSocketObject = _sockets[socketId];
    
    long result = send(currentSocketObject, [buffer buffer], [buffer bufferUsedSize], 0);
    if(result < 0) {
        if(errno == EWOULDBLOCK) {
            NSLog(@"Async");
        } else {
            NSLog(@"Failed to send message with size: %ul", [buffer bufferUsedSize]);
            [self validateResult: -1];
        }
    }
}

- (void)sendBuffer:(ByteBuffer *)buffer {
    _currentSocket++;
    _currentSocket = _currentSocket % _numSockets;
    [self sendBuffer:buffer toSocketWithId:_currentSocket];
}
@end
