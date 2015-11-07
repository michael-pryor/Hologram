//
//  SoundEncodingShared.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import "SoundEncodingShared.h"

NSString *NSStringFromOSStatus(OSStatus errCode) {
    if (errCode == noErr)
        return @"noErr";
    char message[5] = {0};
    *(UInt32 *) message = CFSwapInt32HostToBig(errCode);
    NSString *code = [NSString stringWithCString:message encoding:NSASCIIStringEncoding];
    NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errCode userInfo:nil];
    return [NSString stringWithFormat:@"[%@]: %@", code, [error debugDescription]];
}

bool HandleResultOSStatus(OSStatus errCode, NSString *performing, bool shouldLogSuccess) {
    if (errCode == noErr) {
        if (shouldLogSuccess) {
            NSLog(performing);
        }
        return true;
    }

    NSString *errorMessage = NSStringFromOSStatus(errCode);

    NSLog(@"While %@ the following error occurred: %@", performing, errorMessage);
    return false;
}

int calculateBufferSize(AudioStreamBasicDescription *audioDescription) {
    return 1024;
}