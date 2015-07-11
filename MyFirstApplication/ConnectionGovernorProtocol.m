//
//  ConnectionManagerProtocol.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/01/2015.
//
//

#import "ConnectionGovernorProtocol.h"
#import "ConnectionManagerTcp.h"
#import "ConnectionManagerUdp.h"
#import "InputSessionTcp.h"
#import "OutputSessionTcp.h"
#import "EventTracker.h"
#import "ActivityMonitor.h"

uint NUM_SOCKETS = 1;

// Session hash has timed out, you need a fresh session.
#define REJECT_HASH_TIMEOUT 1

@implementation ConnectionGovernorProtocol {
    id<NewPacketDelegate> _recvDelegate;
    ConnectionManagerUdp* _udpConnection;
    ConnectionManagerTcp* _tcpConnection;
    OutputSessionTcp* _tcpOutputSession;
    ConnectionStatusProtocol _connectionStatus;
    id<ConnectionStatusDelegateProtocol> _connectionStatusDelegate;
    NSObject* _connectionStatusLock;
    
    // For reconnect attempts after TCP failure.
    NSString* _udpHash;
    ByteBuffer* _udpHashPacket;
    EventTracker* _failureTracker;
    
    NSString* _tcpHost;
    NSString* _udpHost;
    ushort _tcpPort;
    ushort _udpPort;
    
    ActivityMonitor* _reconnectMonitor;
    
    // Must be kept in sync with server.
    #define OP_REJECT_LOGON 1
    #define OP_ACCEPT_LOGON 2
    #define OP_ACCEPT_UDP 3
}

- (id)initWithRecvDelegate:(id<NewPacketDelegate>)recvDelegate unknownRecvDelegate:(id<NewUnknownPacketDelegate>)unknownRecvDelegate connectionStatusDelegate:(id<ConnectionStatusDelegateProtocol>)connectionStatusDelegate slowNetworkDelegate:(id<SlowNetworkDelegate>)slowNetworkDelegate {
    self = [super init];
    if(self) {
        _udpHash = nil;
        _udpHashPacket = nil;
        
        _recvDelegate = recvDelegate;
        _connectionStatusDelegate = connectionStatusDelegate;
        _connectionStatus = P_NOT_CONNECTED;
        _connectionStatusLock = [[NSObject alloc] init];
        
        _failureTracker = [[EventTracker alloc] initWithMaxEvents:500];
        
        [_connectionStatusDelegate connectionStatusChange:P_NOT_CONNECTED withDescription:@"Not yet connected"];
        
        InputSessionTcp* tcpSession = [[InputSessionTcp alloc] initWithDelegate:self];
        _tcpOutputSession = [[OutputSessionTcp alloc] init];
        _tcpConnection = [[ConnectionManagerTcp alloc] initWithConnectionStatusDelegate:self inputSession:tcpSession outputSession:_tcpOutputSession];
        
        _udpConnection = [[ConnectionManagerUdp alloc] initWithNewPacketDelegate:self newUnknownPacketDelegate:unknownRecvDelegate slowNetworkDelegate:slowNetworkDelegate connectionDelegate:self retryCount:5];
        
        [self _setupReconnectMonitor];
    }
    return self;
}

- (void) _setupReconnectMonitor {
    _reconnectMonitor = [[ActivityMonitor alloc] initWithAction: ^{
        [self reconnect];
    } andBackoff:1];
}

/**
    Connection handshaking process goes like this:
    1. We connect via TCP and UDP.
    2. We send version and login via TCP.
    3. We wait for acceptance or reject (WAITING_FOR_TCP_LOGON_ACK).
        4. If reject then end connection and report error to user.
    5. If acceptance, will contain UDP hash.
    6. Send UDP hash via UDP repeatedly until TCP ack received, or until timeout (WAITING_FOR_UDP_HASH_ACK).
    7. On TCP ACK connection is setup (CONNECTED).
 */
- (void) connectToTcpHost:(NSString*)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString*)udpHost udpPort:(ushort)udpPort {
    _tcpHost = tcpHost;
    _udpHost = udpHost;
    _tcpPort = tcpPort;
    _udpPort = udpPort;
    
    [_reconnectMonitor terminate];
    [self _setupReconnectMonitor];
    
    [self reconnect];
}

- (void) reconnect {
    NSLog(@"Connecting to TCP: %@:%ul, UDP: %@:%ul", _tcpHost, _tcpPort, _udpHost, _udpPort);
    [self updateConnectionStatus:P_CONNECTING withDescription:@"Connecting..."];
    
    [_tcpConnection connectToHost:_tcpHost andPort:_tcpPort];
    [_udpConnection connectToHost:_udpHost andPort:_udpPort];
}

- (void) reconnectLimitedWithFailureDescription:(NSString*)failureDescription {
    NSLog(@"Terminating entire connection due to failure: %@", failureDescription);
    [self shutdownWithDescription:failureDescription];

    // We may get lots of different reconnect requests from different threads at roughly
    // the same time. The idea here is that for all of those we do one reconnect.
    // reconnectMonitor has a back off configured in its initialization, so long as
    // all reconnect requests come in within that backoff then only one reconnect will be done.
    if(![_failureTracker increment]) {
        NSLog(@"Signaling reconnect request due to failure: %@", failureDescription);
        [_reconnectMonitor performAction];
    }
}

- (Boolean) updateConnectionStatus:(ConnectionStatusProtocol)connectionStatus withDescription:(NSString*)description {
    if(connectionStatus == P_CONNECTED) {
        [_failureTracker reset];
    }
    
    @synchronized(_connectionStatusLock) {
        if(_connectionStatus != connectionStatus) {
            _connectionStatus = connectionStatus;
            [_connectionStatusDelegate connectionStatusChange:connectionStatus withDescription:description];
            return true;
        } else {
            return false;
        }
    }
}

- (void) shutdownWithDescription:(NSString*)description {
    if([self updateConnectionStatus:P_NOT_CONNECTED withDescription:description]) {
        [_tcpConnection shutdown];
        [_udpConnection shutdown];
    }
}

- (void) shutdown {
    [self shutdownWithDescription:@"Disconnected"];
}

- (Boolean)isConnected {
    return [_tcpConnection isConnected] && [_udpConnection isConnected];
}

- (void) sendTcpPacket:(ByteBuffer*)packet {
    [_tcpOutputSession onNewPacket:packet fromProtocol:TCP];
}

- (void) sendUdpPacket:(ByteBuffer*)packet {
    [_udpConnection onNewPacket:packet fromProtocol:UDP];
}

- (void)sendUdpPacket:(ByteBuffer*)packet toPreparedAddress:(uint)address toPreparedPort:(ushort)port {
    [_udpConnection sendBuffer:packet toPreparedAddress:address toPreparedPort:port];
}

- (void)sendUdpPacket:(ByteBuffer*)packet toAddress:(NSString*)address toPort:(ushort)port {
    [_udpConnection sendBuffer:packet toAddress:address toPort:port];
}

- (void) sendUdpLogonHash: (ByteBuffer*)bufferToSend {
    if(_connectionStatus == P_WAITING_FOR_UDP_HASH_ACK) {
        NSLog(@"Sending UDP hash logon attempt..");
      
        [_udpConnection sendBuffer:bufferToSend];
        [self triggerUdpLogonHashSendAsync:bufferToSend]; // We need to repeatedly send this until timeout.
    }
}

- (void) triggerUdpLogonHashSendAsync: (ByteBuffer*)bufferToSend {
    [self performSelector: @selector(sendUdpLogonHash:) withObject: bufferToSend afterDelay:0.5];
}

- (void)handleRejectCode:(uint)rejectCode {
    // Hash timed out, the next one will succeed if we clear it (server will give us a new one).
    if(rejectCode == REJECT_HASH_TIMEOUT) {
        _udpHash = nil;
    }
}

- (void) onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol{
    if(protocol == TCP) {
        if(_connectionStatus != P_CONNECTED ) {
            uint logon = [packet getUnsignedInteger];
            
            if(_connectionStatus == P_WAITING_FOR_TCP_LOGON_ACK) {
                if(logon == OP_REJECT_LOGON) {
                    uint rejectCode = [packet getUnsignedInteger];
                    [self handleRejectCode:rejectCode];
                    NSString* rejectReason = [packet getString];
                    NSString* rejectDescription = [@"Logon rejected with reason: " stringByAppendingString:rejectReason];
                    [self shutdownWithDescription:rejectDescription];
                } else if(logon == OP_ACCEPT_LOGON) {
                    _udpHash = [packet getString];
                    _udpHashPacket = [[ByteBuffer alloc] init];
                
                    NSLog(@"Login accepted, sending UDP hash packet with hash: %@", _udpHash);
                    [_udpHashPacket addString: _udpHash];

                    _connectionStatus = P_WAITING_FOR_UDP_HASH_ACK;
                    [self sendUdpLogonHash:_udpHashPacket];
                } else {
                    [self shutdownWithDescription:@"Invalid login op code"];
                }
            } else if(_connectionStatus == P_WAITING_FOR_UDP_HASH_ACK) {
                if(logon == OP_ACCEPT_UDP) {
                    NSLog(@"UDP hash accepted, fully connected");
                    [self updateConnectionStatus:P_CONNECTED withDescription:@"Connected!"];
                } else {
                    [self shutdownWithDescription:@"Invalid hash ack op code"];
                }
            } else {
                [self shutdownWithDescription:@"Invalid connection state"];
            }
            return;
        } else {
            NSLog(@"New TCP packet received with size: %ul", [packet bufferUsedSize]);
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        if(_connectionStatus != P_CONNECTED) {
            // This is valid, UDP may come through faster than TCP.
            NSLog(@"Received UDP packet prior to connection ACK, discarding");
            return;
        } else {
            //NSLog(@"New UDP packet received with size: %ul", [packet bufferUsedSize]);
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    }
}

- (void) connectionStatusChangeTcp: (ConnectionStatusTcp)status withDescription: (NSString*)description {
    if(status == T_CONNECTING) {
        // Nothing to do here, we preemptively reported this when starting the connection attempt.
    } else if(status == T_ERROR) {
        if(_connectionStatus != P_NOT_CONNECTED) {
            NSString* rejectDescription = [@"TCP connection failed: " stringByAppendingString:description];
            [self reconnectLimitedWithFailureDescription:rejectDescription];
        }
    } else if(status == T_CONNECTED) {
        NSLog(@"Connected, sending login request");
        _connectionStatus = P_WAITING_FOR_TCP_LOGON_ACK;
        ByteBuffer* theLogonBuffer = [[ByteBuffer alloc] init];
        [theLogonBuffer addUnsignedInteger:100];                // version
        [theLogonBuffer addString:@"My name is Michael"];       // login name
        // We are reconnecting, identify our session via the UDP hash.
        if(_udpHash != nil) {
            [theLogonBuffer addString:_udpHash];
        }
        [self sendTcpPacket:theLogonBuffer];
    } else {
        [self shutdownWithDescription:@"Invalid TCP state"];
    }
}

- (void) connectionStatusChangeUdp: (ConnectionStatusUdp)status withDescription: (NSString*)description {
    if(status == U_ERROR) {
        NSString* rejectDescription = [@"UDP connection failed: " stringByAppendingString:description];
        [self reconnectLimitedWithFailureDescription:rejectDescription];
    } else if(status == U_CONNECTED) {
        // TCP handles connection signal, nothing to do here.
    } else {
        [self shutdownWithDescription:@"Invalid UDP state"];
    }
}


- (id<NewPacketDelegate>) getTcpOutputSession {
    return [[ConnectionGovernorProtocolTcpSession alloc] initWithConnectionManager:self];
}
- (id<NewPacketDelegate>) getUdpOutputSession {
    return [[ConnectionGovernorProtocolUdpSession alloc] initWithConnectionManager:self];
}
@end