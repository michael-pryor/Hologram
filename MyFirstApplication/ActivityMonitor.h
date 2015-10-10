//
//  ConnectionMonitor.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 03/05/2015.
//
//

#import <Foundation/Foundation.h>

@interface ActivityMonitor : NSObject
- (id)initWithAction:(void (^)(void))action andBackoff:(float)backoffTimeSeconds;

- (void)performAction;

- (void)terminate;
@end
