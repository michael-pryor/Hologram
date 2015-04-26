//
//  Connectivity.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionManagerTcp.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import "OutputSessionTcp.h"
#import "Signal.h"

@implementation ConnectionManagerTcp {
    NSInputStream * _inputStream;
    NSOutputStream * _outputStream;
    id<NewDataDelegate> _inputSession;
    OutputSessionTcp * _outputSession;
    ByteBuffer * _currentSendBuffer;
    Signal* _initializedSignal;
    Signal* _shutdownSignal;
    NSThread* _outputThread;
}

- (id) initWithConnectionStatusDelegate: (id<ConnectionStatusDelegateTcp>)connectionStatusDelegate inputSession: (id<NewDataDelegate>)inputSession outputSession: (OutputSessionTcp*)outputSession {
    self = [super init];
    if(self) {
        _connectionStatusDelegate = connectionStatusDelegate;
        _inputSession = inputSession;
        _outputSession = outputSession;
        _initializedSignal = [[Signal alloc] initWithFlag:false];
        _shutdownSignal = [[Signal alloc] initWithFlag:true];
    }
    return self;
}

- (void) outputThreadEntryPoint: var {
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream open];
    
    NSLog(@"Finished initializing output thread");
    [_initializedSignal signal]; // finished initializing.

    NSLog(@"Starting run loop");
    CFRunLoopRun();
    NSLog(@"Finished run loop");
    
    [_shutdownSignal signal]; // finished shutting down.
    NSLog(@"Output thread exiting");
}

- (void) _doConnectToHost: (NSString*)host andPort: (ushort)port {
    [_connectionStatusDelegate connectionStatusChangeTcp:T_CONNECTING withDescription:@"Connecting"];
    
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStringRef remoteHost = (__bridge CFStringRef)(host);
    CFStreamCreatePairWithSocketToHost(NULL, remoteHost, port, &readStream, &writeStream);
    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    
    _inputStream = objc_unretainedObject(readStream);
    _outputStream = objc_unretainedObject(writeStream);
    
    [_outputStream setDelegate: self];
    [_inputStream setDelegate: self];
    
    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_inputStream open];
    
    [_initializedSignal clear]; // not finished initializing yet.
    [_shutdownSignal clear]; // not shutdown yet.
    
    // Run send operations in a seperate run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _outputThread = [[NSThread alloc] initWithTarget:self
                                            selector:@selector(outputThreadEntryPoint:)
                                              object:nil];
    [_outputThread start];
    NSLog(@"Output thread started");
}

- (void) connectToHost: (NSString*)host andPort: (ushort)port; {
    if([NSThread isMainThread]) {
        [self _doConnectToHost:host andPort:port];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _doConnectToHost:host andPort:port];
        });
    }
    
    [_initializedSignal wait];
    NSLog(@"Fully initialized");
}

- (void) performShutdownInRunLoop {
    NSLog(@"Terminating run loop and closing output stream");
    [self onNormalError: _outputStream withError:@"Terminating TCP connection"];
    NSLog(@"Closing input stream");
    [self closeStream: _inputStream];
}

- (void) shutdown {
    if(![self isConnected]) {
        return;
    }
    
    NSLog(@"Waking up output thread");
    [_outputSession onNewPacket:nil fromProtocol:UDP];
    
    NSLog(@"Terminating run loop and closing streams");
    @try {
        [self performSelector: @selector(performShutdownInRunLoop) onThread: _outputThread withObject: nil waitUntilDone: true];
    } @catch(NSException* ex) {
        NSLog(@"NSException, oh dear: %@", ex);
    }
    NSLog(@"Waiting for confirmation of closure");
    [_shutdownSignal wait];
    NSLog(@"Confirmation of closure received");
}

- (void) restart {
    [self shutdown];
    [_outputSession restartSession];
}

- (Boolean) isConnected {
    return ![_shutdownSignal isSignaled];
}

- (void) closeStream: (NSStream*)stream withStatus: (ConnectionStatusTcp)status andReason: (NSString*)reason {
    [self closeStream: stream];
    NSString * description = [NSString localizedStringWithFormat:@"Connection closed, with reason: %@", reason];
    [_connectionStatusDelegate connectionStatusChangeTcp:status withDescription:description];
}

- (void) closeStream: (NSStream*) stream {
    if (stream == _outputStream) {
        // Stop the worker thread.
        NSLog(@"Closing output stream thread!! OH MY!!");
        CFRunLoopStop(CFRunLoopGetCurrent());
    }

    [stream close];
}

- (void)onStreamError: (NSStream*)theStream {
    NSString * streamError = [NSString localizedStringWithFormat:@"Stream error detected, details: [%@]", [[theStream streamError] localizedDescription]];
    [self closeStream:theStream withStatus:T_ERROR andReason:streamError];
}

- (void)onNormalError: (NSStream*)theStream withError: (NSString*)errorText {
    NSString * streamError = [NSString localizedStringWithFormat:@"Error detected, details: [%@]", errorText];
    [self closeStream:theStream withStatus:T_ERROR andReason:streamError];
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    Boolean isInputStream = (theStream == _inputStream);
    Boolean isOutputStream = !isInputStream;
    
    switch(streamEvent) {
        case NSStreamEventNone:
            [self onNormalError: theStream withError: @"Streams terminating with event none"];
            break;
            
        case NSStreamEventOpenCompleted:
            // Send for only one stream, don't want to duplicate the message.
            if(isOutputStream) {
                [_connectionStatusDelegate connectionStatusChangeTcp:T_CONNECTED withDescription:@"Connection open"];
            }
            break;
            
        case NSStreamEventHasBytesAvailable:
            if(isInputStream) {
                ByteBuffer* dataStream = [_inputSession getDestinationBuffer];
                
                // Double memory size if we run out.
                // TODO: Consider perhaps a smarter solution to this.
                [dataStream increaseMemoryIfUnusedAt:0 to:dataStream.bufferMemorySize*2];
                
                // Read in data at the end of currently stored data (just past used size).
                NSInteger bytesRead = [_inputStream read:[dataStream buffer] + [dataStream bufferUsedSize] maxLength:[dataStream getUnusedMemory]];
                if(bytesRead < 0) {
                    [self onStreamError:theStream];
                    return;
                }
                
                Boolean successfulIncreaseInUsedSize = [dataStream increaseUsedSizePassively:(uint)bytesRead];
                if(!successfulIncreaseInUsedSize) {
                    [self onNormalError: theStream withError:@"Failed to increase used size, bad value"];
                    return;
                }
            	
                [_inputSession onNewData: (uint)bytesRead];
        	}
            break;
        case NSStreamEventHasSpaceAvailable:
            if(isOutputStream) {
                if(_currentSendBuffer == nil || [_currentSendBuffer getUnreadDataFromCursor] == 0) {
                    _currentSendBuffer = [_outputSession processPacket];
                    // A nil packet indicates thread termination.
                    // A further message in the run loop queue will close the sockets.
                    if(_currentSendBuffer == nil) {
                        return;
                    }
                    [_currentSendBuffer setCursorPosition:0];
                }                
                
                NSUInteger remaining = [_currentSendBuffer getUnreadDataFromCursor];
                uint8_t* buffer = [_currentSendBuffer buffer] + [_currentSendBuffer cursorPosition];
           
                if(remaining > 0) {
                    NSUInteger bytesSent = [_outputStream write:buffer maxLength:remaining];
                    if(bytesSent == -1) {
                        [self onStreamError:theStream];
                        return;
                    }
                    [_currentSendBuffer moveCursorForwardsPassively:(uint)bytesSent];
                    NSLog(@"%lu TCP bytes sent, %lu remaining", (unsigned long)bytesSent, (unsigned long)[_currentSendBuffer getUnreadDataFromCursor]);
                }                
            }
            break;
            
        case NSStreamEventErrorOccurred:
            [self onStreamError: theStream];
            break;
            
        case NSStreamEventEndEncountered:
            [self onNormalError: theStream withError: @"Streams terminating gracefully"];
            break;
            
        default:
            [self onNormalError: theStream withError: @"Streams terminating with UNKNOWN EVENT!"];
            break;
    }
}
@end
