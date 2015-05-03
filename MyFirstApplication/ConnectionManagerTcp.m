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
#import "InputSessionTcp.h"
#import "Signal.h"

@implementation ConnectionManagerTcp {
    NSInputStream * _inputStream;
    NSOutputStream * _outputStream;
    InputSessionTcp* _inputSession;
    OutputSessionTcp * _outputSession;
    Signal* _initializedSignal;
    Signal* _shutdownSignal;
    Signal* _notInProcessOfShuttingDownSignal;
    NSThread* _outputThread;
    dispatch_queue_t _connectionQueue;
}

- (id) initWithConnectionStatusDelegate: (id<ConnectionStatusDelegateTcp>)connectionStatusDelegate inputSession: (InputSessionTcp*)inputSession outputSession: (OutputSessionTcp*)outputSession {
    self = [super init];
    if(self) {
        _connectionQueue = dispatch_queue_create("ConnectionManagerTcpQueue", NULL);
        _connectionStatusDelegate = connectionStatusDelegate;
        _inputSession = inputSession;
        _outputSession = outputSession;
        _initializedSignal = [[Signal alloc] initWithFlag:false];
        _shutdownSignal = [[Signal alloc] initWithFlag:true];
        _notInProcessOfShuttingDownSignal = [[Signal alloc] initWithFlag:true];
    }
    return self;
}

- (void) outputThreadEntryPoint: var {
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream open];
    [_outputSession loadOutputStream:_outputStream];
    
    [_initializedSignal signal]; // finished initializing.

    NSLog(@"TCP output - Starting run loop");
    CFRunLoopRun();
    
    [_shutdownSignal signal]; // finished shutting down.
    NSLog(@"TCP output - Finished run loop, output thread exiting");
}

- (void) connectToHost: (NSString*)host andPort: (ushort)port; {
    [self shutdown];
    
    // So that sockets/streams are owned by main thread.
    dispatch_sync(_connectionQueue, ^{
        // Do not try to setup a new connection when in the middle of shutting down (thread safety).
        [_notInProcessOfShuttingDownSignal wait];
    
        [_outputSession restartSession];
        [_inputSession restartSession];
     
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
    });
    
    [_initializedSignal wait];
    NSLog(@"TCP connection - Fully initialized");
}

- (void) performShutdownInRunLoop {
    NSLog(@"TCP output - Terminating run loop and closing streams");
    [self onNormalError: _outputStream withError:@"Terminating TCP connection"];
    [self closeStream: _inputStream];
}

- (void) shutdown {
    // If no socket to destroy
    // or already completely shutdown
    // or already in the process of shutting down (if not, signal is cleared and we allow continuation).
    if(![self isConnected] || [_shutdownSignal isSignaled] || ![_notInProcessOfShuttingDownSignal clear]) {
        return;
    }

    [_outputSession onNewPacket:nil fromProtocol:UDP];
    
    @try {
        [self performSelector: @selector(performShutdownInRunLoop) onThread: _outputThread withObject: nil waitUntilDone: false];
    } @catch(NSException* ex) {
        NSLog(@"TCP - NSException while shutting down run loop: %@", ex);
    }
    [_shutdownSignal wait];
    NSLog(@"TCP - Termination complete");
    
    // Finished shutting down.
    [_notInProcessOfShuttingDownSignal signal];
}

- (Boolean) isConnected {
    return ![_shutdownSignal isSignaled];
}

- (void) closeStream: (NSStream*)stream withStatus: (ConnectionStatusTcp)status andReason: (NSString*)reason {
    [self closeStream: stream];
    // Don't report errors upstream if these are errors caused by shutdown process (we don't care, we want it to die).
    if([_notInProcessOfShuttingDownSignal isSignaled]) {
        NSString * description = [NSString localizedStringWithFormat:@"Connection closed, with reason: %@", reason];
        [_connectionStatusDelegate connectionStatusChangeTcp:status withDescription:description];
    }
}

- (void) closeStream: (NSStream*) stream {
    if (stream == _outputStream) {
        // Stop the worker thread.
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
                Boolean success = [_outputSession doSendOperation];
                if(!success) {
                    [self onStreamError:_outputStream];
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
