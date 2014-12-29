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

@implementation ConnectionManager
@synthesize connectionStatusDelegate;
NSInputStream * inputStream;
NSOutputStream * outputStream;
id<NewDataDelegate> inputSession;
OutputSession * outputSession;
dispatch_queue_t queue;

bool _isConnected = false;
NSCondition * isConnectedCondition;

- (id) initWithDelegate: (id<ConnectionStatusDelegate>)p_connectionStatusDelegate inputSession: (id<NewDataDelegate>)p_inputSession outputSession: (OutputSession*)outputSession {
    self = [super init];
    if(self) {
        connectionStatusDelegate = p_connectionStatusDelegate;
        inputSession = p_inputSession;
        isConnectedCondition = [[NSCondition alloc] init];
    }
    return self;
}

- (void) myMethod {
    NSLog(@"Hello world");
    AudioServicesPlaySystemSound(0x450);
}


- (void) outputThreadEntryPoint: var {
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream open];
    
    [isConnectedCondition lock];
    _isConnected = true;
    [isConnectedCondition broadcast];
    [isConnectedCondition unlock];
    
    CFRunLoopRun();
    
    [outputSession confirmClosure];
    NSLog(@"Thread exiting... LOL");
}

- (void) connect {
    [connectionStatusDelegate connectionStatusChange:CONNECTING withDescription:@"Connecting"];
        
    queue = dispatch_queue_create("my queue", NULL);

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStringRef remoteHost = (__bridge CFStringRef)(CONNECT_IP);
    CFStreamCreatePairWithSocketToHost(NULL, remoteHost, CONNECT_PORT, &readStream, &writeStream);
    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

    inputStream = objc_unretainedObject(readStream);
    outputStream = objc_unretainedObject(writeStream);

    [outputStream setDelegate: self];
    [inputStream setDelegate: self];

    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream open];
    
    NSThread* outputThread = [[NSThread alloc] initWithTarget:self
                                               selector:@selector(outputThreadEntryPoint:)
                                               object:nil];
    [outputThread start];
    
    NSLog(@"Waiting for connection to complete");
    [isConnectedCondition lock];
    while(!_isConnected) {
        [isConnectedCondition wait];
    }
    [isConnectedCondition unlock];
    NSLog(@"Connection completed");
}


- (void) closeWithStatus: (ConnectionStatus)status andReason: (NSString*)reason {
    if(inputStream != nil) {
        NSLog(@"Closing input stream");
        [self closeStream: inputStream];
    }
    if(outputStream != nil) {
        NSLog(@"Closing output stream");
        [self closeStream: outputStream];
    }
    NSString * description = [NSString localizedStringWithFormat:@"Connection closed, with reason: %@", reason];
    [connectionStatusDelegate connectionStatusChange:status withDescription:description];
}

- (void) closeStream: (NSStream*) stream {
    [stream close];
    if (stream == outputStream) {
        // Stop the worker thread.
        NSLog(@"Closing output stream thread!! OH MY!!");
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

- (void)onStreamError: (NSStream*)theStream {
    NSString * streamError = [NSString localizedStringWithFormat:@"Stream error detected, details: [%@]", [[theStream streamError] localizedDescription]];
    [self closeWithStatus:ERROR_CON andReason:streamError];
}

- (void)onNormalError: (NSString*)errorText {
    NSString * streamError = [NSString localizedStringWithFormat:@"Error detected, details: [%@]", errorText];
    [self closeWithStatus:ERROR_CON andReason:streamError];
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    Boolean isInputStream = (theStream == inputStream);
    Boolean isOutputStream = !isInputStream;
    
    if(isInputStream) {
        NSLog(@"Received input stream result: %lu",streamEvent);
    } else {
        NSLog(@"Received output stream result: %lu",streamEvent);
    }
    
    switch(streamEvent) {
        case NSStreamEventNone:
            [self onNormalError: @"Streams terminating with event none"];
            break;
            
        case NSStreamEventOpenCompleted:
            [connectionStatusDelegate connectionStatusChange:OK_CON withDescription:@"Connection open"];
            break;
            
        case NSStreamEventHasBytesAvailable:
            if(isInputStream) {
                ByteBuffer* dataStream = [inputSession getDestinationBuffer];
                
                // Double memory size if we run out.
                // TODO: Consider perhaps a smarter solution to this.
                [dataStream increaseMemoryIfUnusedAt:0 to:dataStream.bufferMemorySize*2];
                
                // Read in data at the end of currently stored data (just past used size).
                NSInteger bytesRead = [inputStream read:[dataStream buffer] + [dataStream bufferUsedSize] maxLength:[dataStream getUnusedMemory]];
                if(bytesRead < 0) {
                    [self onStreamError:theStream];
                    return;
                }
                
                Boolean successfulIncreaseInUsedSize = [dataStream increaseUsedSizePassively:(uint)bytesRead];
                if(!successfulIncreaseInUsedSize) {
                    [self onNormalError:@"Failed to increase used size, bad value"];
                    return;
                }
            	
                [inputSession onNewData: (uint)bytesRead];
        	}
            break;
        case NSStreamEventHasSpaceAvailable:
            if(isOutputStream) {
                ByteBuffer * packetToSend = [outputSession processPacket];
                if(packetToSend == nil) {
                    [self onNormalError:@"Termination of stream"];
                    return;
                }
                
                NSLog(@"Packet prepared for sending on output stream, length: %u", [packetToSend bufferUsedSize]);
                
                NSUInteger remaining = [packetToSend bufferUsedSize];
                uint8_t* buffer = [packetToSend buffer];
                while(remaining > 0) {
                    NSUInteger bytesSent = [outputStream write:buffer maxLength:remaining];
                    buffer += bytesSent;
                    remaining -= bytesSent;
                    NSLog(@"%lu bytes sent, %lu remaining", (unsigned long)bytesSent, (unsigned long)remaining);
                }
            }
            break;
            
        case NSStreamEventErrorOccurred:
            [self onStreamError: theStream];
            break;
            
        case NSStreamEventEndEncountered:
            [self onNormalError: @"Streams terminating gracefully"];
            break;
            
        default:
            [self onNormalError: @"Streams terminating with UNKNOWN EVENT!"];
            break;
    }
}
@end
