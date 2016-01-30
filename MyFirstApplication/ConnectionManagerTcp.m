//
//  Connectivity.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionManagerTcp.h"
#import "Signal.h"
#import "Threading.h"

@implementation ConnectionManagerTcp {
    NSInputStream *_inputStream;
    NSOutputStream *_outputStream;
    InputSessionTcp *_inputSession;
    OutputSessionTcp *_outputSession;
    Signal *_shutdownSignal;
}

- (id)initWithConnectionStatusDelegate:(id <ConnectionStatusDelegateTcp>)connectionStatusDelegate inputSession:(InputSessionTcp *)inputSession outputSession:(OutputSessionTcp *)outputSession {
    self = [super init];
    if (self) {
        _connectionStatusDelegate = connectionStatusDelegate;
        _inputSession = inputSession;
        _outputSession = outputSession;
        _shutdownSignal = [[Signal alloc] initWithFlag:true];
    }
    return self;
}

- (void)_doConnectToHost:(NSString *)host andPort:(ushort)port {
    [self shutdown];

    [_outputSession restartSession];
    [_inputSession restartSession];

    [_connectionStatusDelegate connectionStatusChangeTcp:T_CONNECTING withDescription:@"Connecting"];

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStringRef remoteHost = (__bridge CFStringRef) (host);
    CFStreamCreatePairWithSocketToHost(NULL, remoteHost, port, &readStream, &writeStream);
    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

    _inputStream = objc_unretainedObject(readStream);
    _outputStream = objc_unretainedObject(writeStream);

    [_outputStream setDelegate:self];
    [_inputStream setDelegate:self];

    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream open];
    [_outputSession loadOutputStream:_outputStream];

    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_inputStream open];

    [_shutdownSignal clear]; // not shutdown yet.
}

- (void)connectToHost:(NSString *)host andPort:(ushort)port; {
    // So that sockets/streams are owned by main thread.
    dispatch_sync_main(^{
        [self _doConnectToHost:host andPort:port];
    });
}

- (void)shutdown {
    if (![_shutdownSignal signal]) {
        return;
    }

    [self closeStream:_outputStream];
    [self closeStream:_inputStream];
}

- (Boolean)isConnected {
    return ![_shutdownSignal isSignaled];
}

- (void)closeStream:(NSStream *)stream withStatus:(ConnectionStatusTcp)status andReason:(NSString *)reason {
    [self closeStream:stream];

    NSString *description = [NSString localizedStringWithFormat:@"Connection closed, with reason: %@", reason];
    [_connectionStatusDelegate connectionStatusChangeTcp:status withDescription:description];
}

- (void)closeStream:(NSStream *)stream {
    [stream close];
}

- (void)onStreamError:(NSStream *)theStream {
    NSString *streamError = [NSString localizedStringWithFormat:@"Stream error detected, details: [%@]", [[theStream streamError] localizedDescription]];
    [self closeStream:theStream withStatus:T_ERROR andReason:streamError];
}

- (void)onNormalError:(NSStream *)theStream withError:(NSString *)errorText {
    NSString *streamError = [NSString localizedStringWithFormat:@"Error detected, details: [%@]", errorText];
    [self closeStream:theStream withStatus:T_ERROR andReason:streamError];
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    Boolean isInputStream = (theStream == _inputStream);
    Boolean isOutputStream = (theStream == _outputStream);

    if (!isInputStream && !isOutputStream) {
        NSLog(@"TCP - ignoring notification, old message from prior connection");
        return;
    }

    switch (streamEvent) {
        case NSStreamEventNone:
            [self onNormalError:theStream withError:@"Streams terminating with event none"];
            break;

        case NSStreamEventOpenCompleted:
            // Send for only one stream, don't want to duplicate the message.
            if (isOutputStream) {
                NSLog(@"TCP connection - Fully initialized");
                [_connectionStatusDelegate connectionStatusChangeTcp:T_CONNECTED withDescription:@"Connection open"];
            }
            break;

        case NSStreamEventHasBytesAvailable:
            if (isInputStream) {
                ByteBuffer *dataStream = [_inputSession getDestinationBuffer];

                // Double memory size if we run out.
                // TODO: Consider perhaps a smarter solution to this.
                [dataStream increaseMemoryIfUnusedAt:0 to:dataStream.bufferMemorySize * 2];

                // Read in data at the end of currently stored data (just past used size).
                NSInteger bytesRead = [_inputStream read:[dataStream buffer] + [dataStream bufferUsedSize] maxLength:[dataStream getUnusedMemory]];
                if (bytesRead < 0) {
                    [self onStreamError:theStream];
                    return;
                }

                Boolean successfulIncreaseInUsedSize = [dataStream increaseUsedSizePassively:(uint) bytesRead];
                if (!successfulIncreaseInUsedSize) {
                    [self onNormalError:theStream withError:@"Failed to increase used size, bad value"];
                    return;
                }

                [_inputSession onNewData:(uint) bytesRead];
            }
            break;
        case NSStreamEventHasSpaceAvailable:
            if (isOutputStream) {
                Boolean success = [_outputSession doSendOperation];
                if (!success) {
                    [self onStreamError:_outputStream];
                }
            }
            break;

        case NSStreamEventErrorOccurred:
            [self onStreamError:theStream];
            break;

        case NSStreamEventEndEncountered:
            [self onNormalError:theStream withError:@"Streams terminating gracefully"];
            break;

        default:
            [self onNormalError:theStream withError:@"Streams terminating with UNKNOWN EVENT!"];
            break;
    }
}
@end
