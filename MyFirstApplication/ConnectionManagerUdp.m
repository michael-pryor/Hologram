//
//  ConnectionManagerUdp.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import "ConnectionManagerUdp.h"
#import "EventTracker.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#import <netdb.h>
#include "NetworkUtility.h"
#include "IPV6Resolver.h"
#include "Signal.h"
#include "ReadWriteLock.h"

@implementation ConnectionManagerUdp {
    int _socketV4; // IP version 4
    int _socketV6; // IP version 6

    dispatch_source_t _dispatchSourceV4;
    dispatch_source_t _dispatchSourceV6;

    dispatch_queue_t _gcdReceivingQueue;
    dispatch_queue_t _gcdSendingQueue;

    id <NewPacketDelegate> _newPacketDelegate;
    id <ConnectionStatusDelegateUdp> _connectionDelegate;
    ByteBuffer *_recvBuffer;
    EventTracker *_sendFailureEventTracker;
    struct sockaddr *_primaryConnectAddress;
    uint _primaryConnectAddressLength;
    id <NewUnknownPacketDelegate> _newUnknownPacketDelegate;
    IPV6Resolver *_addressResolver;

    struct addrinfo *_allConnectAddresses;

    Signal *_closingNotInProgress;
    Signal *_openingNotInProgress;

    // Critical section of _allConnectAddresses, _primaryConnectAddress and _primaryConnectAddressLength.
    ReadWriteLock *_connectAddressRwLock;
}

- (id)initWithNewPacketDelegate:(id <NewPacketDelegate>)newPacketDelegate newUnknownPacketDelegate:(id <NewUnknownPacketDelegate>)newUnknownPacketDelegate connectionDelegate:(id <ConnectionStatusDelegateUdp>)connectionDelegate retryCount:(uint)retryCountMax {
    self = [super init];
    if (self) {
        _socketV4 = 0;
        _socketV6 = 0;
        _dispatchSourceV4 = nil;
        _dispatchSourceV6 = nil;
        _connectionDelegate = connectionDelegate;
        _newPacketDelegate = newPacketDelegate;
        _recvBuffer = [[ByteBuffer alloc] init];
        _gcdReceivingQueue = dispatch_queue_create("ConnectionManagerUdp", NULL);
        _gcdSendingQueue = dispatch_queue_create("ConnectionManagerUdpSendQueue", NULL);
        _sendFailureEventTracker = [[EventTracker alloc] initWithMaxEvents:retryCountMax];
        _newUnknownPacketDelegate = newUnknownPacketDelegate;
        _addressResolver = [[IPV6Resolver alloc] init];
        _allConnectAddresses = nil;
        _primaryConnectAddress = nil;
        _primaryConnectAddressLength = 0;

        _closingNotInProgress = [[Signal alloc] initWithFlag:true];
        _openingNotInProgress = [[Signal alloc] initWithFlag:true];
        _connectAddressRwLock = [[ReadWriteLock alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (int)getSocket {
    if ([self isUsingIPV4]) {
        return _socketV4;
    } else {
        return _socketV6;
    }
}

- (bool)isUsingIPV4 {
    [_connectAddressRwLock lockForReading];
    @try {
        return _primaryConnectAddress->sa_family == AF_INET;
    } @finally {
        [_connectAddressRwLock unlock];
    }
}

- (void)onFailure {
    int err = errno;
    NSString *description = [NSString localizedStringWithFormat:@"UDP connection failure, with reason: %d", err];
    NSLog(@"%@", description);
    [self close];
    [_connectionDelegate connectionStatusChangeUdp:U_ERROR withDescription:description];
}

- (void)close {
    [_closingNotInProgress wait];
    if ([self isConnected] && _dispatchSourceV4 != nil) {
        NSLog(@"UDP - Closing socket");
        [_closingNotInProgress clear];

        dispatch_source_cancel(_dispatchSourceV4);
        close(_socketV4);
        _socketV4 = 0;

        dispatch_source_cancel(_dispatchSourceV6);
        close(_socketV6);
        _socketV6 = 0;
    }
    [_closingNotInProgress signalAll];
}

- (void)shutdown {
    [self close];
}

- (Boolean)isConnected {
    return _socketV4 != 0;
}

- (void)onRecvIPV4 {
    struct sockaddr_in recvAddress = {0};
    recvAddress.sin_family = AF_INET;
    [self onRecvFromSocket:_socketV4 addressStructure:(struct sockaddr *) &recvAddress addressStructureSize:sizeof(recvAddress)];
}

- (void)onRecvIPV6 {
    struct sockaddr_in6 recvAddress = {0};
    recvAddress.sin6_family = AF_INET6;
    [self onRecvFromSocket:_socketV6 addressStructure:(struct sockaddr *) &recvAddress addressStructureSize:sizeof(recvAddress)];
}

// No need for synchronization here, we don't update dependant data structures unless sockets are closed.
- (void)onRecvFromSocket:(int)socket addressStructure:(struct sockaddr *)recvAddress addressStructureSize:(uint)recvAddressSize {
    // dispatch_source_get_data seems to always return 1 after we switch the host we send/receive data to/from.
    // so this looks like a bug.
    //
    // Instead we now fix the max size of packets we can handle to 2048, which should be more than enough for UDP.
    long maximumAmountReceivable = 2048; //dispatch_source_get_data(_dispatch_source);
    ssize_t realAmountReceived;

    if (maximumAmountReceivable > [_recvBuffer bufferMemorySize]) {
        [_recvBuffer setMemorySize:(uint) maximumAmountReceivable retaining:false];
    }

    realAmountReceived = recvfrom(socket, [_recvBuffer getRawDataPtr], maximumAmountReceivable, 0, recvAddress, &recvAddressSize);

    // This would cause buffer overrun and indicates a serious bug somewhere (probably not in our code though *puts on sunglasses slowly*).
    if (realAmountReceived == -1) {
        NSLog(@"UDP - Serious receive error detected while attempting to receive data");
        [self onFailure];
        return;
    }
    if (realAmountReceived > maximumAmountReceivable) {
        NSLog(@"UDP - Receive error detected: %zu (real) vs %ld (maximum)", realAmountReceived, maximumAmountReceivable);
        [self onFailure];
        return;
    }

    [_recvBuffer setUsedSize:(uint) realAmountReceived];

    //NSLog(@"UDP - Received packet of size: %ul", [_recvBuffer bufferUsedSize]);
    [_connectAddressRwLock lockForReading];
    @try {
        struct addrinfo *address;
        for (address = _allConnectAddresses; address != nil; address = address->ai_next) {
            if ([NetworkUtility isEqualAddress:address->ai_addr address:recvAddress]) {
                [_newPacketDelegate onNewPacket:_recvBuffer fromProtocol:UDP];
                return;
            }
        }
    } @finally {
        [_connectAddressRwLock unlock];
    }

    // If is IP4 we can do NAT punchthrough.
    if (recvAddress->sa_family == AF_INET) {
        struct sockaddr_in *recvAddressIPV4 = (struct sockaddr_in *) recvAddress;
        [_newUnknownPacketDelegate onNewPacket:_recvBuffer fromProtocol:UDP fromAddress:recvAddressIPV4->sin_addr.s_addr andPort:recvAddressIPV4->sin_port];
    } else {
        if (recvAddress->sa_family == AF_INET6) {
            NSLog(@"Dropping unknown data in IPV6 mode");
        } else {
            NSLog(@"Dropping unknown data in unknown mode: %i", recvAddress->sa_family);
        }
    }
}

- (int)buildSocketWithDomain:(int)domain outDispatchSource:(__strong dispatch_source_t *)outDispatchSource {
    int socketRef = socket(domain, SOCK_DGRAM, 0);
    dispatch_source_t dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) socketRef, 0, _gcdReceivingQueue);

    if (domain == AF_INET) {
        dispatch_source_set_event_handler(dispatchSource, ^{
            [self onRecvIPV4];
        });
    } else {
        dispatch_source_set_event_handler(dispatchSource, ^{
            [self onRecvIPV6];
        });
    }

    dispatch_resume(dispatchSource);
    *outDispatchSource = dispatchSource;

    return socketRef;
}

- (void)connectToHost:(NSString *)host andPort:(ushort)port {
    [self close];

    [_sendFailureEventTracker reset];

    // Termination of socket happens asynchronously, make sure we don't reconnect
    // midway through termination.
    [_closingNotInProgress wait];
    [_openingNotInProgress clear];

    [_connectAddressRwLock lockForWriting];
    @try {
        _primaryConnectAddress = nil;
        _primaryConnectAddressLength = 0;
        _allConnectAddresses = [_addressResolver retrieveAddressesFromHost:host withPort:port];
        [self updatePrimaryConnectAddress];
    } @finally {
        [_connectAddressRwLock unlock];
    }

    _socketV4 = [self buildSocketWithDomain:AF_INET outDispatchSource:&_dispatchSourceV4];
    _socketV6 = [self buildSocketWithDomain:AF_INET6 outDispatchSource:&_dispatchSourceV6];

    [_openingNotInProgress signalAll];

    [_connectionDelegate connectionStatusChangeUdp:U_CONNECTED withDescription:@"Successfully connected"];
    NSLog(@"UDP - Connected socket to host %@ and port %u", host, port);
}

- (void)onNewPacket:(ByteBuffer *)buffer fromProtocol:(ProtocolType)protocol {
    [self sendBuffer:buffer];
}

- (void)sendBuffer:(ByteBuffer *)buffer toPreparedAddress:(uint)address toPreparedPort:(ushort)port {
    if (![self isUsingIPV4]) {
        return;
    }

    struct sockaddr_in toAddress;
    memset(&toAddress, 0, sizeof(toAddress));
    toAddress.sin_family = AF_INET;
    toAddress.sin_addr.s_addr = INADDR_ANY;

    toAddress.sin_port = port;
    toAddress.sin_addr.s_addr = address;

    [self sendBuffer:buffer toAddress:(struct sockaddr *) &toAddress addressLength:sizeof(toAddress)];
}

- (void)sendBuffer:(ByteBuffer *)buffer toAddress:(NSString *)address toPort:(ushort)port {
    [self sendBuffer:buffer toPreparedAddress:inet_addr([address UTF8String]) toPreparedPort:htons(port)];
}

- (void)copyConnectAddress:(struct sockaddr **)outConnectAddress length:(uint *)outConnectAddressLength {
    [_connectAddressRwLock lockForReading];
    @try {
        *outConnectAddress = malloc(_primaryConnectAddressLength);
        memcpy(*outConnectAddress, _primaryConnectAddress, _primaryConnectAddressLength);
        (*outConnectAddressLength) = _primaryConnectAddressLength;
    } @finally {
        [_connectAddressRwLock unlock];
    }
}

- (void)sendBuffer:(ByteBuffer *)buffer {
    if ([self isConnected]) {
        uint primaryConnectAddressLength;
        struct sockaddr * primaryConnectAddress;
        @try {
            [self copyConnectAddress:&primaryConnectAddress length:&primaryConnectAddressLength];
            [self sendBuffer:buffer toAddress:primaryConnectAddress addressLength:primaryConnectAddressLength];
        } @finally {
            free (primaryConnectAddress);
        }
    }
}

- (bool)updatePrimaryConnectAddressUsingLock {
    [_connectAddressRwLock lockForWriting];
    @try {
        return [self updatePrimaryConnectAddress];
    } @finally {
        [_connectAddressRwLock unlock];
    }
}

- (bool)updatePrimaryConnectAddress {
    bool consumeNextOne = false;
    struct addrinfo *address;
    for (address = _allConnectAddresses; address != nil; address = address->ai_next) {
        if (_primaryConnectAddress == nil) {
            consumeNextOne = true;
        } else if (address->ai_addr == _primaryConnectAddress) {
            consumeNextOne = true;
            continue;
        }
        if (!consumeNextOne) {
            continue;
        }

        _primaryConnectAddress = address->ai_addr;
        _primaryConnectAddressLength = address->ai_addrlen;
        return true;
    }
    return false;
}

- (void)sendBuffer:(ByteBuffer *)buffer toAddress:(struct sockaddr *)address addressLength:(uint)length {
    dispatch_sync(_gcdSendingQueue, ^{
        long result;
        if (![self isConnected]) {
            return;
        }
        [_openingNotInProgress wait];

        result = sendto([self getSocket], [buffer buffer], [buffer bufferUsedSize], 0, address, length);
        if (result < 0) {
            if ([_sendFailureEventTracker increment]) {
                if (![self updatePrimaryConnectAddressUsingLock]) {
                    [self onFailure];
                } else {
                    [_sendFailureEventTracker reset];
                }
            } else {
                int err = errno;
                float waitForSeconds = [_sendFailureEventTracker getNumEvents] * 0.2;
                NSLog(@"UDP - Non fatal failure to send message with size: %ul, reason: %d, backoff time: %f", [buffer bufferUsedSize], err, waitForSeconds);
                [NSThread sleepForTimeInterval:waitForSeconds];
            }
        } else {
            [_sendFailureEventTracker reset];
        }
    });
}
@end
