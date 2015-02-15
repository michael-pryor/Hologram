//
//  Batcher.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "PipelineProcessor.h"
#import "OutputSessionBase.h"

/**
 * Takes a packet as input, augments it in some way and pushes it to the output session.
 */
@implementation PipelineProcessor
- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession {
    self = [super init];
    if(self) {
        _outputSession = outputSession;
    }
    return self;
}
@end
