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


- (id) initWithDelegate: (id<ConnectionStatusDelegate>)p_connectionStatusDelegate inputSession: (id<NewDataDelegate>)inputSession outputSession: (OutputSession*)outputSession {
    self = [super init];
    if(self) {
        self.connectionStatusDelegate = p_connectionStatusDelegate;
    }
    return self;
}

- (void) myMethod {
    NSLog(@"Hello world");
    AudioServicesPlaySystemSound(0x450);
}

- (void) connect {
    [connectionStatusDelegate connectionStatusChange:CONNECTING withDescription:@"Connecting"];
    
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
            [connectionStatusDelegate connectionStatusChange:OK withDescription:@"Connection open"];
            break;
            
        case NSStreamEventHasBytesAvailable:
            if(isInputStream) {
                ByteBuffer* dataStream = [inputSession getDestinationBuffer];
                
                // should we be using cursor or used size! ?? im too tired.
                
                // Double memory size if we run out.
                [dataStream increaseMemoryIfUnusedAt:0 to:dataStream.bufferMemorySize*2];
                
                // Read in data.
                [inputStream read:[dataStream buffer] maxLength:[dataStream getUnusedMemory]];
            }
            break;
            
        case NSStreamEventHasSpaceAvailable:
            if(isOutputStream) {
                // Here we need to know what data to send. Need some sort of queue. Abstract this out to another class.
                // should be an interface (a.k.a protocol?).
            }
            break;
            
        case NSStreamEventErrorOccurred:
            description = [NSString localizedStringWithFormat:@"Stream error detected in %@, details: [%@]", streamName, [[theStream streamError] localizedDescription]];
            [connectionStatusDelegate connectionStatusChange:ERROR withDescription:description];
            break;
            
        case NSStreamEventEndEncountered:
            break;
    }
}
@end
