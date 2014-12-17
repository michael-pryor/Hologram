//
//  OutputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "ByteBuffer.h"

@interface OutputSession : NSObject
{
    @private
    NSMutableArray *queue;
}
@property (nonatomic, strong) NSCondition * _lock;

- (id) init;
- (void) sendPacket: (ByteBuffer*) packet;
- (ByteBuffer*) processPacket;
@end
