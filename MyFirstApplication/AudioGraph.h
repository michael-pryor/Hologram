//
// Created by Michael Pryor on 17/02/2016.
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
@import AudioToolbox;

@interface AudioGraph : NSObject<NewPacketDelegate>
- (AudioUnit)getAudioProducer;

- (void)initialize;

- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession leftPadding:(uint)leftPadding;
@end