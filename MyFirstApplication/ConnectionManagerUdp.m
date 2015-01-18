//
//  ConnectionManagerUdp.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 18/01/2015.
//
//

#import "ConnectionManagerUdp.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
@implementation ConnectionManagerUdp {
    int socObject;
}
- (void) validateResult: (int)result {
    if(result < 0) {
        NSLog(@"UDP networking failure, reason %ul", errno);
    }
}

- (void) connectToHost: (NSString*) host andPort: (ushort) port {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr([host UTF8String]);
    
    socObject = socket(AF_INET, SOCK_DGRAM, 0);
    [self validateResult: connect(socObject, (const struct sockaddr *)&addr, sizeof(addr))];
}

- (void) sendBuffer: (ByteBuffer*)buffer {
    int result = send(socObject, [buffer buffer], [buffer bufferUsedSize], 0);
    [self validateResult: result];
}
@end
