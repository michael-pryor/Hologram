//
// Created by Michael Pryor on 05/03/2016.
//

#import <Foundation/Foundation.h>

#include "Timer.h"


@interface TimedCounter : NSObject
@property (readonly) uint lastTotal;
- (bool)incrementBy:(uint)amount;
- (id)initWithTimer:(Timer*)timer;
@end