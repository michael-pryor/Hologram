//
//  ConnectionManagerProtocol.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/01/2015.
//
//

#import "ConnectionGovernorProtocol.h"
#import "EventTracker.h"
#import "ActivityMonitor.h"
#import "Timer.h"
#import "NetworkOperations.h"
#import "BannedViewController.h"
#import "UniqueId.h"

// Session hash has timed out, you need a fresh session.
#define REJECT_HASH_TIMEOUT 1

// Server wants a newer version.
#define REJECT_BAD_VERSION 2

// You were banned from the server previously, and so cannot join.
#define REJECT_BANNED 3

// Payment could not be verified.
#define REJECT_KARMA_REGENERATION_FAILED 4

// Need a new persisted ID, because the one we generated is already in use by someone else.
#define PERSISTED_ID_CLASH 5

// Version to include in connection attempts.
// Must be >= to server's expectation, otherwise we'l be rejected.
#define VERSION 4

// Client has been inactive (not accepting or rejecting conversations) for too long.
#define INACTIVE_TIMOUT 6

@implementation ConnectionGovernorProtocol {
    id <NewPacketDelegate> _recvDelegate;
    ConnectionManagerUdp *_udpConnection;
    ConnectionManagerTcp *_tcpConnection;
    OutputSessionTcp *_tcpOutputSession;
    ConnectionStatusProtocol _connectionStatus;
    id <ConnectionStatusDelegateProtocol> _connectionStatusDelegate;
    NSObject *_connectionStatusLock;

    // For reconnect attempts after TCP failure.
    NSString *_udpHash;
    ByteBuffer *_udpHashPacket;
    EventTracker *_failureTracker;
    Boolean _reconnectEnabled;

    NSString *_tcpHost;
    NSString *_udpHost;
    ushort _tcpPort;
    ushort _udpPort;

    ActivityMonitor *_reconnectMonitor;
    id <LoginProvider> _loginProvider;

    NSThread *_pingThread;
    Boolean _alive;
    Boolean _isNewSession;

    Boolean _exitDialogShown;

    UIAlertView *_alertUpdateApplication;
    UIAlertView *_karmaRegenerationFailed;

    // Must be kept in sync with server.
#define OP_REJECT_LOGON 1
#define OP_ACCEPT_LOGON 2
#define OP_ACCEPT_UDP 3
#define OP_PING 10
}

- (id)initWithRecvDelegate:(id <NewPacketDelegate>)recvDelegate unknownRecvDelegate:(id <NewUnknownPacketDelegate>)unknownRecvDelegate connectionStatusDelegate:(id <ConnectionStatusDelegateProtocol>)connectionStatusDelegate loginProvider:(id <LoginProvider>)loginProvider {
    self = [super init];
    if (self) {
        _alive = true;
        _reconnectEnabled = true;

        _udpHash = nil;
        _udpHashPacket = nil;

        _recvDelegate = recvDelegate;
        _connectionStatusDelegate = connectionStatusDelegate;
        _connectionStatus = P_NOT_CONNECTED;
        _connectionStatusLock = [[NSObject alloc] init];

        _failureTracker = [[EventTracker alloc] initWithMaxEvents:500];

        [_connectionStatusDelegate connectionStatusChange:P_NOT_CONNECTED withDescription:@"Not yet connected"];

        InputSessionTcp *tcpSession = [[InputSessionTcp alloc] initWithDelegate:self];
        _tcpOutputSession = [[OutputSessionTcp alloc] init];
        _tcpConnection = [[ConnectionManagerTcp alloc] initWithConnectionStatusDelegate:self inputSession:tcpSession outputSession:_tcpOutputSession];

        _udpConnection = [[ConnectionManagerUdp alloc] initWithNewPacketDelegate:self newUnknownPacketDelegate:unknownRecvDelegate connectionDelegate:self retryCount:5];

        _loginProvider = loginProvider;
        _exitDialogShown = false;

        [self _setupReconnectMonitor];

        _pingThread = [[NSThread alloc] initWithTarget:self
                                              selector:@selector(_pingThreadEntryPoint:)
                                                object:nil];
        [_pingThread setName:@"Pinger"];
        [_pingThread start];

        _alertUpdateApplication = [[UIAlertView alloc] initWithTitle:@"Please update the application"
                                                        message:nil
                                                       delegate:self
                                              cancelButtonTitle:@"Exit"
                                              otherButtonTitles:nil];

        _karmaRegenerationFailed = [[UIAlertView alloc] initWithTitle:@"Karma Regeneration Failed"
                                                             message:nil
                                                            delegate:self
                                                   cancelButtonTitle:@"Retry"
                                                   otherButtonTitles:@"Abort", nil];
    }
    return self;
}

- (void)_setupReconnectMonitor {
    _reconnectMonitor = [[ActivityMonitor alloc] initWithAction:^{
        [self reconnect];
    }                                                andBackoff:1];
}

- (void)_pingThreadEntryPoint:var {
    ByteBuffer *pingBuffer = [[ByteBuffer alloc] init];
    [pingBuffer addUnsignedInteger8:OP_PING];

    Timer *pingTimer = [[Timer alloc] initWithFrequencySeconds:2 firingInitially:false];

    while (_alive) {
        [pingTimer blockUntilNextTick];
        if (_connectionStatus == P_CONNECTED) {
            [_tcpOutputSession onNewPacket:pingBuffer fromProtocol:TCP];

            // Send UDP route detection packet, in case our external IP or port changes, we want the server to know
            // and to fix itself.
            if (_udpHashPacket != nil) {
                [_udpConnection sendBuffer:_udpHashPacket];
            }
        }
    }
    NSLog(@"Ping thread exiting");
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
- (void)connectToTcpHost:(NSString *)tcpHost tcpPort:(ushort)tcpPort udpHost:(NSString *)udpHost udpPort:(ushort)udpPort {
    _tcpHost = tcpHost;
    _udpHost = udpHost;
    _tcpPort = tcpPort;
    _udpPort = udpPort;

    [_reconnectMonitor terminate];
    [self _setupReconnectMonitor];

    [self reconnect];
}

- (void)disableReconnecting {
    NSLog(@"Governor reconnect attempts disabled");
    _reconnectEnabled = false;
}

- (void)reconnect {
    NSLog(@"Connecting to TCP: %@:%ul, UDP: %@:%ul", _tcpHost, _tcpPort, _udpHost, _udpPort);
    [self updateConnectionStatus:P_CONNECTING withDescription:@"Connecting..."];

    [_tcpConnection connectToHost:_tcpHost andPort:_tcpPort];
    [_udpConnection connectToHost:_udpHost andPort:_udpPort];
}

- (void)reconnectLimitedWithFailureDescription:(NSString *)failureDescription {
    NSLog(@"Terminating entire connection due to failure: %@", failureDescription);
    [self shutdownWithDescription:failureDescription];

    // We may get lots of different reconnect requests from different threads at roughly
    // the same time. The idea here is that for all of those we do one reconnect.
    // reconnectMonitor has a back off configured in its initialization, so long as
    // all reconnect requests come in within that backoff then only one reconnect will be done.
    if (_reconnectEnabled && ![_failureTracker increment]) {
        NSLog(@"Signaling reconnect request due to failure: %@", failureDescription);
        [_reconnectMonitor performAction];
    }
}

- (Boolean)updateConnectionStatus:(ConnectionStatusProtocol)connectionStatus withDescription:(NSString *)description {
    ConnectionStatusProtocol auxStatus;
    if (connectionStatus == P_CONNECTED_TO_EXISTING) {
        auxStatus = P_CONNECTED;
    } else {
        auxStatus = connectionStatus;
    }

    if (auxStatus == P_CONNECTED) {
        [_failureTracker reset];
    }

    @synchronized (_connectionStatusLock) {
        if (_connectionStatus != auxStatus) {
            _connectionStatus = auxStatus;
            [_connectionStatusDelegate connectionStatusChange:connectionStatus withDescription:description];
            return true;
        } else {
            return false;
        }
    }
}

- (void)shutdownWithDescription:(NSString *)description {
    [self shutdownWithConnectionStatus:P_NOT_CONNECTED withDescription:description];
}

- (void)shutdownWithConnectionStatus:(ConnectionStatusProtocol)connectionStatus withDescription:(NSString *)description {
    if ([self updateConnectionStatus:connectionStatus withDescription:description]) {
        [_tcpConnection shutdown];
        [_udpConnection shutdown];
    }
}

- (void)terminate {
    [self terminateWithConnectionStatus:P_NOT_CONNECTED withDescription:@"Disconnected"];
}

- (void)terminateWithConnectionStatus:(ConnectionStatusProtocol)connectionStatus withDescription:(NSString *)description {
    _alive = false;
    [self shutdownWithConnectionStatus:connectionStatus withDescription:description];
    [_reconnectMonitor terminate];
}

- (Boolean)isTerminated {
    return !_alive;
}

- (void)shutdown {
    [self shutdownWithDescription:@"Disconnected"];
}

- (Boolean)isConnected {
    return [_tcpConnection isConnected] && [_udpConnection isConnected];
}

- (void)sendTcpPacket:(ByteBuffer *)packet {
    [_tcpOutputSession onNewPacket:packet fromProtocol:TCP];
}

- (void)sendUdpPacket:(ByteBuffer *)packet {
    if (_connectionStatus != P_CONNECTED) {
        return;
    }

    [_udpConnection onNewPacket:packet fromProtocol:UDP];
}

- (void)sendUdpPacket:(ByteBuffer *)packet toPreparedAddress:(uint)address toPreparedPort:(ushort)port {
    if (_connectionStatus != P_CONNECTED) {
        return;
    }

    [_udpConnection sendBuffer:packet toPreparedAddress:address toPreparedPort:port];
}

- (void)sendUdpPacket:(ByteBuffer *)packet toAddress:(NSString *)address toPort:(ushort)port {
    if (_connectionStatus != P_CONNECTED) {
        return;
    }
    [_udpConnection sendBuffer:packet toAddress:address toPort:port];
}

- (void)sendUdpLogonHash:(ByteBuffer *)bufferToSend {
    if (_connectionStatus == P_WAITING_FOR_UDP_HASH_ACK && _alive) {
        NSLog(@"Sending UDP hash logon attempt..");

        [_udpConnection sendBuffer:bufferToSend];
        [self triggerUdpLogonHashSendAsync:bufferToSend]; // We need to repeatedly send this until timeout.
    }
}

- (void)triggerUdpLogonHashSendAsync:(ByteBuffer *)bufferToSend {
    [self performSelector:@selector(sendUdpLogonHash:) withObject:bufferToSend afterDelay:0.5];
}

- (void)handleRejectCode:(uint)rejectCode description:(NSString *)rejectDescription packet:(ByteBuffer *)packet {
    // Hash timed out, the next one will succeed if we clear it (server will give us a new one).
    if (rejectCode == REJECT_HASH_TIMEOUT) {
        [self terminateWithConnectionStatus:P_NOT_CONNECTED_HASH_REJECTED withDescription:@"Session expired"];
        [self reconnectLimitedWithFailureDescription:rejectDescription];
    } else if (rejectCode == PERSISTED_ID_CLASH) {
        [self terminateWithConnectionStatus:P_NOT_CONNECTED_HASH_REJECTED withDescription:@"Persisted ID is already in use"];
        [[UniqueId getUniqueIdInstance] refreshUUID];
        [self reconnectLimitedWithFailureDescription:rejectDescription];
    } else if (rejectCode == REJECT_BAD_VERSION) {
        [self disableReconnecting];
        if (_exitDialogShown) {
            return;
        }
        _exitDialogShown = true;

        NSString *alertText = [NSString stringWithFormat:@"The version of the application you are running is too old; please update it in the Apple app store.\n\nThe server rejected our connection request with details: [%@]", rejectDescription];
        [_alertUpdateApplication setMessage:alertText];
        [_alertUpdateApplication show];
    } else if (rejectCode == REJECT_BANNED) {
        [self disableReconnecting];
        uint8_t magnitude = [packet getUnsignedInteger8];
        uint expiryTimeSeconds = [packet getUnsignedInteger];
        [_connectionStatusDelegate onBannedWithMagnitude:magnitude expiryTimeSeconds:expiryTimeSeconds];
    } else if (rejectCode == REJECT_KARMA_REGENERATION_FAILED) {
        [self terminateWithConnectionStatus:P_NOT_CONNECTED withDescription:@"Karma regeneration failed"];
        [_karmaRegenerationFailed setMessage:rejectDescription];
        [_karmaRegenerationFailed show];
    } else if (rejectCode == INACTIVE_TIMOUT) {
        [self terminateWithConnectionStatus:P_NOT_CONNECTED withDescription:rejectDescription];
        [_connectionStatusDelegate onInactivityRejection];
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView == _alertUpdateApplication) {
        if ([alertView cancelButtonIndex] == buttonIndex) {
            NSLog(@"Exiting the application because rejected by server (bad version)");
            exit(0);
        }
    } else if (alertView == _karmaRegenerationFailed) {
        if ([alertView cancelButtonIndex] != buttonIndex) {
            // We think this receipt will repeatedly fail, so reconnect again without it.
            [_loginProvider clearKarmaRegeneration];
        }
        [self reconnect];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    if (protocol == TCP) {
        uint logon = [packet getUnsignedInteger8];
        if (logon == OP_REJECT_LOGON) {
            uint rejectCode = [packet getUnsignedInteger8];
            NSString *rejectReason = [packet getString];
            if (rejectReason == nil) {
                rejectReason = @"[No reject reason]";
            }

            [self handleRejectCode:rejectCode description:rejectReason packet:packet];
            return;
        }

        if (_connectionStatus != P_CONNECTED) {
            if (_connectionStatus == P_WAITING_FOR_TCP_LOGON_ACK) {
                if (logon == OP_ACCEPT_LOGON) {
                    // UUID must be valid now.
                    [[UniqueId getUniqueIdInstance] onValidatedUUID];

                    NSLog(@"Login accepted, sending UDP hash packet with hash: %@", _udpHash);

                    // We've used our Karma regeneration transaction, don't use it again.
                    [_loginProvider clearKarmaRegeneration];

                    _isNewSession = _udpHash == nil;
                    if (_isNewSession) {
                        _udpHash = [packet getString];
                        _udpHashPacket = [[ByteBuffer alloc] init];
                        [_udpHashPacket addUnsignedInteger8:UDP_HASH];
                        [_udpHashPacket addString:_udpHash];
                    }

                    _connectionStatus = P_WAITING_FOR_UDP_HASH_ACK;
                    [self sendUdpLogonHash:_udpHashPacket];
                } else {
                    [self shutdownWithDescription:@"Invalid login op code"];
                }
            } else if (_connectionStatus == P_WAITING_FOR_UDP_HASH_ACK) {
                if (logon == OP_ACCEPT_UDP) {
                    NSLog(@"UDP hash accepted, fully connected");
                    if (_isNewSession) {
                        [self updateConnectionStatus:P_CONNECTED withDescription:@"Connected!"];
                    } else {
                        [self updateConnectionStatus:P_CONNECTED_TO_EXISTING withDescription:@"Connected!"];
                    }
                } else {
                    [self shutdownWithDescription:@"Invalid hash ack op code"];
                }
            } else {
                [self shutdownWithDescription:@"Invalid connection state"];
            }
            return;
        } else {
            NSLog(@"New TCP packet received with size: %ul", [packet bufferUsedSize]);
            [packet setCursorPosition:0];
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    } else {
        if (_connectionStatus != P_CONNECTED) {
            // This is valid, UDP may come through faster than TCP.
            NSLog(@"Received UDP packet prior to connection ACK, discarding");
            return;
        } else {
            //NSLog(@"New UDP packet received with size: %ul", [packet bufferUsedSize]);
            [_recvDelegate onNewPacket:packet fromProtocol:protocol];
        }
    }
}

- (void)connectionStatusChangeTcp:(ConnectionStatusTcp)status withDescription:(NSString *)description {
    if (status == T_CONNECTING) {
        // Nothing to do here, we preemptively reported this when starting the connection attempt.
    } else if (status == T_ERROR) {
        if (_connectionStatus != P_NOT_CONNECTED) {
            if (description == nil) {
                description = @"[No failure description]";
            }
            NSString *rejectDescription = [@"TCP connection failed: " stringByAppendingString:description];
            [self reconnectLimitedWithFailureDescription:rejectDescription];
        }
    } else if (status == T_CONNECTED) {
        NSLog(@"Connected, sending login request");
        _connectionStatus = P_WAITING_FOR_TCP_LOGON_ACK;
        ByteBuffer *theLogonBuffer = [[ByteBuffer alloc] init];

        // If we are reconnecting, identify our session via the UDP hash.
        uint8_t val = (_udpHash != nil) ? 1 : 0;
        [theLogonBuffer addUnsignedInteger8:val];
        if (_udpHash != nil) {
            [theLogonBuffer addString:_udpHash];
        }

        // Version.
        [theLogonBuffer addUnsignedInteger:VERSION];

        // The login part.
        [theLogonBuffer addByteBuffer:[_loginProvider getLoginBuffer] includingPrefix:false];

        [self sendTcpPacket:theLogonBuffer];
    } else {
        [self shutdownWithDescription:@"Invalid TCP state"];
    }
}

- (void)connectionStatusChangeUdp:(ConnectionStatusUdp)status withDescription:(NSString *)description {
    if (status == U_ERROR) {
        if (description == nil) {
            description = @"[No failure description]";
        }
        NSString *rejectDescription = [@"UDP connection failed: " stringByAppendingString:description];
        [self reconnectLimitedWithFailureDescription:rejectDescription];
    } else if (status == U_CONNECTED) {
        // TCP handles connection signal, nothing to do here.
    } else {
        [self shutdownWithDescription:@"Invalid UDP state"];
    }
}


- (id <NewPacketDelegate>)getTcpOutputSession {
    return [[ConnectionGovernorProtocolTcpSession alloc] initWithConnectionManager:self];
}

- (id <NewPacketDelegate>)getUdpOutputSession {
    return [[ConnectionGovernorProtocolUdpSession alloc] initWithConnectionManager:self];
}
@end
