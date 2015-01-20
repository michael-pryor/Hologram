//
//  InputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "InputSessionBase.h"

@interface InputSessionTCP : NSObject<NewDataDelegate>
@property (readonly) ByteBuffer* getDestinationBuffer;
@property (readonly) id<NewPacketDelegate> packetDelegate;
- (id) initWithDelegate: (id<NewPacketDelegate>)packetDelegate;
@end


