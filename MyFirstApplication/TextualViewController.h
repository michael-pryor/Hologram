//
// Created by Michael Pryor on 16/09/2016.
//

#import <Foundation/Foundation.h>
#import "CircleCountdownTimer.h"
#import "SingleViewCollection.h"

@interface TextualViewController : UIViewController<TimeoutDelegate>
- (void)stop;

- (void)reset;
@end