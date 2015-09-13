//
//  Batcher.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"
#import "InputSessionBase.h"

@interface PipelineProcessor : NSObject<NewPacketDelegate> {
    @protected
    id<NewPacketDelegate> _outputSession;
}

- (id) initWithOutputSession:(id<NewPacketDelegate>)outputSession;
- (void)setOutputSession:(id<NewPacketDelegate>)session;
@end
