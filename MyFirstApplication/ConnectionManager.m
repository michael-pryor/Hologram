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

- (id) initWithDelegate: (id<ConnectionStatusDelegate>)p_connectionStatusDelegate inputSession: (id<NewDataDelegate>)p_inputSession outputSession: (OutputSession*)outputSession {
    self = [super init];
    if(self) {
        connectionStatusDelegate = p_connectionStatusDelegate;
        inputSession = p_inputSession;
    }
    return self;
}

- (void) myMethod {
    NSLog(@"Hello world");
    AudioServicesPlaySystemSound(0x450);
}

- (void) connect {
    [connectionStatusDelegate connectionStatusChange:CONNECTING withDescription:@"Connecting"];
        
    queue = dispatch_queue_create("my queue", NULL);

    NSLog(@"helloooooo why are you not running");
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

    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    [inputStream open];
    [outputStream open];
}

- (void) closeWithStatus: (ConnectionStatus)status andReason: (NSString*)reason {
    if(inputStream != nil) {
        NSLog(@"Closing input stream");
        [inputStream close];
    }
    if(outputStream != nil) {
        NSLog(@"Closing output stream");
        [outputStream close];
    }
    NSString * description = [NSString localizedStringWithFormat:@"Connection closed, with reason: %@", reason];
    [connectionStatusDelegate connectionStatusChange:status withDescription:description];
}

- (void)onStreamError: (NSStream*)theStream withStreamName: (NSString*) streamName {
    NSString * streamError = [NSString localizedStringWithFormat:@"Stream error detected in %@, details: [%@]", streamName, [[theStream streamError] localizedDescription]];
    [self closeWithStatus:ERROR_CON andReason:streamError];
}

- (void)onNormalError: (NSString*)errorText withStreamName: (NSString*) streamName {
    NSString * streamError = [NSString localizedStringWithFormat:@"Error detected in %@, details: [%@]", streamName, errorText];
    [self closeWithStatus:ERROR_CON andReason:streamError];
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    Boolean isInputStream = (theStream == inputStream);
    Boolean isOutputStream = !isInputStream;
    
    NSString * streamName;
    if(isInputStream) {
        NSLog(@"Received input stream result: %lu",streamEvent);
        streamName = @"input stream";
    } else {
        NSLog(@"Received output stream result: %lu",streamEvent);
        streamName = @"output stream";
    }
    
    NSString * description;
    switch(streamEvent) {
        case NSStreamEventNone:
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
                    [self onStreamError:theStream withStreamName:streamName];
                    return;
                }
                
                Boolean successfulIncreaseInUsedSize = [dataStream increaseUsedSizePassively:(uint)bytesRead];
                if(!successfulIncreaseInUsedSize) {
                    [self onNormalError:@"Failed to increase used size, bad value" withStreamName:streamName];
                    return;
                }
            	
                [inputSession onNewData: (uint)bytesRead];
        	}
            break;
        case NSStreamEventHasSpaceAvailable:
            if(isOutputStream) {
                ByteBuffer * packetToSend = [outputSession processPacket];
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
            description = [NSString localizedStringWithFormat:@"Stream error detected in %@, details: [%@]", streamName, [[theStream streamError] localizedDescription]];
            [connectionStatusDelegate connectionStatusChange:ERROR_CON withDescription:description];
            break;
            
        case NSStreamEventEndEncountered:
            break;
    }
}
@end
