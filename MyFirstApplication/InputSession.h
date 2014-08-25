//
//  InputSession.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/08/2014.
//
//

#import <Foundation/Foundation.h>

@protocol InputSession
- (void) onRecvData: (NSInteger)bytesReadIntoBuffer;
@property (readonly) uint8_t* buffer;
@property (readonly) int bufferSize;
@end

@interface BufferedPrefixInputSession : NSObject<InputSession>
- (id) init: (int) p_bufferSize;
@end
