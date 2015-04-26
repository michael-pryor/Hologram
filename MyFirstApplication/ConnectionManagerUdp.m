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
#include "EventTracker.h"

@implementation ConnectionManagerUdp {
    int _socket;
    dispatch_queue_t _gcd_queue;
    dispatch_source_t _dispatch_source;
    id<NewPacketDelegate> _newPacketDelegate;
    id<ConnectionStatusDelegateUdp> _connectionDelegate;
    ByteBuffer* _recvBuffer;
    Signal* _closingNotInProgress;
    
    // Failure tracker is used to say; if we fail to setup socket multiple times in a row, we give up. If however
    // we fail / succeed / fail / succeed, we continue doing this indefinitely. Sockets fail regularly e.g.
    // if 3G is unreliabile or switching between 3G and wifi.
    EventTracker* _failureTracker;
    
    // For reconnecting.
    Boolean _matureConnection;
    struct sockaddr_in addr;
}

- (id) initWithNewPacketDelegate:(id<NewPacketDelegate>)newPacketDelegate andConnectionDelegate:(id<ConnectionStatusDelegateUdp>)connectionDelegate andRetryCount:(uint)retryCountMax {
    self = [super init];
    if(self) {
        _socket = 0;
        _connectionDelegate = connectionDelegate;
        _failureTracker = [[EventTracker alloc] initWithMaxEvents:retryCountMax];
        _newPacketDelegate = newPacketDelegate;
        _recvBuffer = [[ByteBuffer alloc] init];
        _closingNotInProgress = [[Signal alloc] initWithFlag:true];
        _gcd_queue = dispatch_queue_create("ConnectionManagerUdp", NULL);
        _matureConnection = false;

        memset(&addr, 0, sizeof(addr));
        
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
    }
    return self;
}

- (void) dealloc {
    [self close];
}

- (void) onSuccess {
    [_failureTracker reset];
}

- (void) onFailure {
    int err = errno;
    NSString * description = [NSString localizedStringWithFormat:@"UDP connection failure, with reason: %d", err];
    NSLog(@"%@",description);
    [self close];
    
    if(![_failureTracker increment]) {
        [self reconnect];
    } else {
        [_connectionDelegate connectionStatusChangeUdp:U_ERROR withDescription:description];
    }
}

- (void) validateResult: (int)result {
    if(result < 0) {
        [self onFailure];
    }
}

- (void) close {
    [_closingNotInProgress wait];
    if([self isConnected] && dispatch_source_testcancel(_dispatch_source) == 0) {
        NSLog(@"Signaling UDP socket closure");
        [_closingNotInProgress clear];
        dispatch_source_cancel(_dispatch_source); // only triggered once, so don't have to worry about multiple calls to this.
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
            NSLog(@"Serious receive error detected while attempting to receive UDP data");
            [self onFailure];
            return;
        }
        if(realAmountReceived > maximumAmountReceivable) {
            NSLog(@"Receive error detected: %zu (real) vs %ld (maximum)", realAmountReceived, maximumAmountReceivable);
            [self onFailure];
            return;
        }
        
        [self onSuccess];
        
        [_recvBuffer setUsedSize: (uint)realAmountReceived];
    
        //NSLog(@"Received UDP packet of size: %ul", [_recvBuffer bufferUsedSize]);
        [_newPacketDelegate onNewPacket:_recvBuffer fromProtocol:UDP];
        
        maximumAmountReceivable -= realAmountReceived;
    } while(maximumAmountReceivable > 0);
}

- (void) reconnect {
    // Termination of socket happens asynchronously, make sure we don't reconnect
    // midway through termination.
    [_closingNotInProgress wait];
    
    NSLog(@"Connecting (or reconnecting) UDP socket");
    _socket = socket(AF_INET, SOCK_DGRAM, 0);
    
    [self validateResult: connect(_socket, (const struct sockaddr *)&addr, sizeof(addr))];
    
    _dispatch_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _socket, 0, _gcd_queue);
    dispatch_source_set_event_handler(_dispatch_source, ^{
        [self onRecv];
    });
    dispatch_source_set_cancel_handler(_dispatch_source, ^{
        NSLog(@"Closing UDP socket");
        close(_socket);
        _socket = 0;
        [_closingNotInProgress signalAll];
    });
    dispatch_resume(_dispatch_source);
    
    if(_matureConnection) {
        [_connectionDelegate connectionStatusChangeUdp:U_RECONNECTED withDescription:@"Successfully reconnected"];
    } else {
        [_connectionDelegate connectionStatusChangeUdp:U_CONNECTED withDescription:@"Successfully connected"];
    }
}

- (void) connectToHost:(NSString*)host andPort:(ushort)port {
    [self close];
    
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr([host UTF8String]);
    
    [self reconnect];
    NSLog(@"Connected UDP socket to host %@ and port %u", host, port);
    _matureConnection = true;
}

- (void)onNewPacket:(ByteBuffer *)buffer fromProtocol:(ProtocolType)protocol {
    [self sendBuffer:buffer];
}

- (void)sendBuffer:(ByteBuffer*)buffer {
    if(![self isConnected]) {
        return;
    }
    
    long result = send(_socket, [buffer buffer], [buffer bufferUsedSize], 0);
    if(result < 0) {
        if(errno == EWOULDBLOCK) {
            NSLog(@"Async");
        } else {
            NSLog(@"Failed to send message with size: %ul", [buffer bufferUsedSize]);
            [self onFailure];
        }
    } else {
        [self onSuccess];
    }
}
@end
