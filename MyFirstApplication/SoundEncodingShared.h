//
//  SoundEncodingShared.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/03/2015.
//
//

#import <Foundation/Foundation.h>

NSString *NSStringFromOSStatus(OSStatus errCode);
void HandleResultOSStatus(OSStatus errCode, NSString* performing, bool fatal);