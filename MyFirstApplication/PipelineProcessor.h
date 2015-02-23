//
//  Batcher.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "OutputSessionBase.h"
#import "InputSessionBase.h"

@interface PipelineProcessor : NSObject<NewPacketDelegate, OutputSessionBase> {
    @protected
    id<OutputSessionBase> _outputSession;
}

- (void)sendPacket:(ByteBuffer*)buffer;
- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession;
@end
