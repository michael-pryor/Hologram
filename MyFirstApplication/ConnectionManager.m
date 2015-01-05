//
//  Connectivity.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionManager.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import "InputSession.h"
#import "OutputSession.h"

static NSString *const CONNECT_IP = @"192.168.1.92";
static const int CONNECT_PORT = 12340;

@implementation ConnectionManager {
    NSInputStream * _inputStream;
    NSOutputStream * _outputStream;
    id<NewDataDelegate> _inputSession;
    OutputSession * _outputSession;
    dispatch_queue_t _queue;
    ByteBuffer * _currentSendBuffer;
}

- (id) initWithDelegate: (id<ConnectionStatusDelegate>)connectionStatusDelegate inputSession: (id<NewDataDelegate>)inputSession outputSession: (OutputSession*)outputSession {
    self = [super init];
    if(self) {
        _connectionStatusDelegate = connectionStatusDelegate;
        _inputSession = inputSession;
        _outputSession = outputSession;
    }
    return self;
}

- (void) outputThreadEntryPoint: var {
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream open];
    
    CFRunLoopRun();
    
    [_outputSession confirmClosure];
    NSLog(@"Output thread exiting");
}

- (void) connect {
    [_connectionStatusDelegate connectionStatusChange:CONNECTING withDescription:@"Connecting"];
        
    _queue = dispatch_queue_create("my queue", NULL);

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStringRef remoteHost = (__bridge CFStringRef)(CONNECT_IP);
    CFStreamCreatePairWithSocketToHost(NULL, remoteHost, CONNECT_PORT, &readStream, &writeStream);
    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

    _inputStream = objc_unretainedObject(readStream);
    _outputStream = objc_unretainedObject(writeStream);

    [_outputStream setDelegate: self];
    [_inputStream setDelegate: self];

    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_inputStream open];
    
    NSThread* outputThread = [[NSThread alloc] initWithTarget:self
                                               selector:@selector(outputThreadEntryPoint:)
                                               object:nil];
    [outputThread start];
}


- (void) closeStream: (NSStream*)stream withStatus: (ConnectionStatus)status andReason: (NSString*)reason {
    [self closeStream: stream];
    NSString * description = [NSString localizedStringWithFormat:@"Connection closed, with reason: %@", reason];
    [_connectionStatusDelegate connectionStatusChange:status withDescription:description];
}

- (void) closeStream: (NSStream*) stream {
    if (stream == _outputStream) {
        // Stop the worker thread.
        NSLog(@"Closing output stream thread!! OH MY!!");
        CFRunLoopStop(CFRunLoopGetCurrent());
    }

    [_inputStream close];
        [_outputStream close];
    [_outputSession sendPacket: (ByteBuffer*)[NSNull null]];
}

- (void)onStreamError: (NSStream*)theStream {
    NSString * streamError = [NSString localizedStringWithFormat:@"Stream error detected, details: [%@]", [[theStream streamError] localizedDescription]];
    [self closeStream:theStream withStatus:ERROR_CON andReason:streamError];
}

- (void)onNormalError: (NSStream*)theStream withError: (NSString*)errorText {
    NSString * streamError = [NSString localizedStringWithFormat:@"Error detected, details: [%@]", errorText];
    [self closeStream:theStream withStatus:ERROR_CON andReason:streamError];
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    Boolean isInputStream = (theStream == _inputStream);
    Boolean isOutputStream = !isInputStream;
    
    if(isInputStream) {
  //      NSLog(@"Received input stream result: %lu",streamEvent);
    } else {
   //     NSLog(@"Received output stream result: %lu",streamEvent);
    }
    
    switch(streamEvent) {
        case NSStreamEventNone:
            [self onNormalError: theStream withError: @"Streams terminating with event none"];
            break;
            
        case NSStreamEventOpenCompleted:
            [_connectionStatusDelegate connectionStatusChange:OK_CON withDescription:@"Connection open"];
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
                    if(_currentSendBuffer == nil) {
                        [self onNormalError: theStream withError:@"Termination of stream"];
                        return;
                    }
                    [_currentSendBuffer setCursorPosition:0];
                }                
                
               // NSLog(@"Packet prepared for sending on output stream, length: %u", [_currentSendBuffer bufferUsedSize]);
                
                NSUInteger remaining = [_currentSendBuffer getUnreadDataFromCursor];
                uint8_t* buffer = [_currentSendBuffer buffer] + [_currentSendBuffer cursorPosition];
           
                if(remaining > 0) {
                    //NSLog(@"Sending..");
                    NSUInteger bytesSent = [_outputStream write:buffer maxLength:remaining];
                    if(bytesSent == -1) {
                        [self onStreamError:theStream];
                        return;
                    }
                    [_currentSendBuffer moveCursorForwardsPassively:(uint)bytesSent];
                   // NSLog(@"%lu bytes sent, %lu remaining", (unsigned long)bytesSent, (unsigned long)[_currentSendBuffer getUnreadDataFromCursor]);
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
