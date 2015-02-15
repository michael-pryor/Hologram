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

@interface PipelineProcessor : NSObject<NewPacketDelegate> {
    @protected
    id<OutputSessionBase> _outputSession;
}

- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession;
@end
