//
//  ThrottledPipe.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import "PipelineProcessor.h"
#import "ThrottledBlock.h"

@interface ThrottledPipe : PipelineProcessor
- (id)initWithOutputSession:(id <NewPacketDelegate>)outputSession defaultOutputFrequency:(CFAbsoluteTime)defaultOutputFrequency;

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol;

- (void)reset;

- (void)slowRate;
@end
