//
//  ConnectionManagerUdp.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import "ConnectionManagerUdp.h"
#import "Signal.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <dispatch/dispatch.h>

@implementation ConnectionManagerUdp {
    int _socket;
    dispatch_queue_t _gcd_queue;
    dispatch_queue_t _gcd_queue_sending;
    dispatch_source_t _dispatch_source;
    id<NewPacketDelegate> _newPacketDelegate;
    id<ConnectionStatusDelegateUdp> _connectionDelegate;
    ByteBuffer* _recvBuffer;
    Signal* _closingNotInProgress;
    Signal* _openingNotInProgress;
}

- (id) initWithNewPacketDelegate:(id<NewPacketDelegate>)newPacketDelegate andConnectionDelegate:(id<ConnectionStatusDelegateUdp>)connectionDelegate andRetryCount:(uint)retryCountMax {
    self = [super init];
    if(self) {
        _socket = 0;
        _connectionDelegate = connectionDelegate;
        _newPacketDelegate = newPacketDelegate;
        _recvBuffer = [[ByteBuffer alloc] init];
        _closingNotInProgress = [[Signal alloc] initWithFlag:true];
        _openingNotInProgress = [[Signal alloc] initWithFlag:true];
        _gcd_queue = dispatch_queue_create("ConnectionManagerUdp", NULL);
        _gcd_queue_sending = dispatch_queue_create("ConnectionManagerUdpSendQueue", NULL);
        _dispatch_source = nil;
    }
    return self;
}

- (void) dealloc {
    [self close];
}

- (void) onFailure {
    int err = errno;
    NSString * description = [NSString localizedStringWithFormat:@"UDP connection failure, with reason: %d", err];
    NSLog(@"%@",description);
    [self close];
    [_connectionDelegate connectionStatusChangeUdp:U_ERROR withDescription:description];
}

- (void) validateResult: (int)result {
    if(result < 0) {
        [self onFailure];
    }
}

- (void) close {
    [_closingNotInProgress wait];
    if([self isConnected] && _dispatch_source != nil) {
        NSLog(@"UDP - Closing socket");
        [_closingNotInProgress clear];
        dispatch_source_cancel(_dispatch_source);
        close(_socket);
        _socket = 0;
        [_closingNotInProgress signalAll];
    }
}

- (void) shutdown {
    [self close];
}
- (Boolean) isConnected {
    return _socket != 0;
}

- (void) onRecv {
    long maximumAmountReceivable = dispatch_source_get_data(_dispatch_source);
    size_t realAmountReceived;
    
    do {
        if(maximumAmountReceivable > [_recvBuffer bufferMemorySize]) {
            [_recvBuffer setMemorySize:(uint)maximumAmountReceivable retaining:false];
        }
        
        realAmountReceived = recv(_socket, [_recvBuffer getRawDataPtr], maximumAmountReceivable, 0);
            
        // This would cause buffer overrun and indicates a serious bug somewhere (probably not in our code though *puts on sunglasses slowly*).
        if(realAmountReceived == -1) {
            NSLog(@"UDP - Serious receive error detected while attempting to receive data");
            [self onFailure];
            return;
        }
        if(realAmountReceived > maximumAmountReceivable) {
            NSLog(@"UDP - Receive error detected: %zu (real) vs %ld (maximum)", realAmountReceived, maximumAmountReceivable);
            [self onFailure];
            return;
        }
        
        [_recvBuffer setUsedSize: (uint)realAmountReceived];
    
        //NSLog(@"UDP - Received packet of size: %ul", [_recvBuffer bufferUsedSize]);
        [_newPacketDelegate onNewPacket:_recvBuffer fromProtocol:UDP];
        
        maximumAmountReceivable -= realAmountReceived;
    } while(maximumAmountReceivable > 0);
}

- (void) connectToHost:(NSString*)host andPort:(ushort)port {
    [self close];
        
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr([host UTF8String]);
    
    // Termination of socket happens asynchronously, make sure we don't reconnect
    // midway through termination.
    [_closingNotInProgress wait];
    [_openingNotInProgress clear];
    
    _socket = socket(AF_INET, SOCK_DGRAM, 0);
    _dispatch_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _socket, 0, _gcd_queue);
    dispatch_source_set_event_handler(_dispatch_source, ^{
        [self onRecv];
    });
    dispatch_resume(_dispatch_source);
    
    [self validateResult: connect(_socket, (const struct sockaddr *)&addr, sizeof(addr))];
    
    
    [_openingNotInProgress signalAll];
    
    [_connectionDelegate connectionStatusChangeUdp:U_CONNECTED withDescription:@"Successfully connected"];
    
    NSLog(@"UDP - Connected socket to host %@ and port %u", host, port);
}

- (void)onNewPacket:(ByteBuffer *)buffer fromProtocol:(ProtocolType)protocol {
    [self sendBuffer:buffer];
}

- (void)sendBuffer:(ByteBuffer*)buffer {
    dispatch_sync(_gcd_queue_sending, ^{
        if(![self isConnected]) {
            return;
        }
        [_openingNotInProgress wait];
        
        long result = send(_socket, [buffer buffer], [buffer bufferUsedSize], 0);
        if(result < 0) {
            if(errno == EWOULDBLOCK) {
                NSLog(@"Async");
            } else {
                NSLog(@"UDP - Failed to send message with size: %ul", [buffer bufferUsedSize]);
                [self onFailure];
            }
        }
    });
}
@end
