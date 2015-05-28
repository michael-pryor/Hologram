//
//  ThrottledBlock.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#import <Foundation/Foundation.h>

@interface ThrottledBlock : NSObject
- (id)initWithDefaultOutputFrequency:(CFAbsoluteTime)defaultOutputFrequency firingInitially:(Boolean)firingInitially;
- (void)reset;
- (void)slowRate;
- (Boolean)runBlock:(void (^)(void))theBlock;
- (CFAbsoluteTime)secondsFrequency;
@end
