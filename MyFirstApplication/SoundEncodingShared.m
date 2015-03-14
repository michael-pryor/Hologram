//
//  SoundEncodingShared.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import "SoundEncodingShared.h"

NSString *NSStringFromOSStatus(OSStatus errCode)
{
    if (errCode == noErr)
        return @"noErr";
    char message[5] = {0};
    *(UInt32*) message = CFSwapInt32HostToBig(errCode);
    NSString* code = [NSString stringWithCString:message encoding:NSASCIIStringEncoding];
    NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errCode userInfo:nil];
    return [NSString stringWithFormat:@"[%@]: %@", code, [error debugDescription]];
}
