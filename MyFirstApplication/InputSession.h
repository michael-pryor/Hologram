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
@end

@interface BufferedPrefixInputSession : NSObject<InputSession>
- (id) init: (int) p_bufferSize;
@end
