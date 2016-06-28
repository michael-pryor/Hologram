//
// Created by Michael Pryor on 25/06/2016.
//

#import <Foundation/Foundation.h>
#import "GAITrackedViewController.h"

@class SKProduct;


@interface BannedViewController : GAITrackedViewController
- (void)setWaitTime:(uint)numSeconds paymentProduct:(SKProduct *)product;
@end