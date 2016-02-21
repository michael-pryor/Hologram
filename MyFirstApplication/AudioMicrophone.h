//
// Created by Michael Pryor on 17/02/2016.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;

@interface AudioMicrophone : NSObject
- (AudioUnit)getIoUnit;
@end