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

void HandleResultOSStatus(OSStatus errCode, NSString* performing, bool fatal) {
    if(errCode == noErr) {
        return;
    }
    
    NSString* errorMessage = NSStringFromOSStatus(errCode);
    
    NSLog(@"While %@ the following error occurred: %@", performing, errorMessage);
//    if(fatal) {
        exit(1);
//    }
}