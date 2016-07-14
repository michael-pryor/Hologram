//
// Created by Michael Pryor on 25/06/2016.
//

#import <Foundation/Foundation.h>
#import <GAITrackedViewController.h>
#import "Payments.h"

@class SKProduct;
@class Payments;


@interface BannedViewController : GAITrackedViewController<TransactionCompletedNotifier>
- (void)setWaitTime:(uint)numSeconds paymentProduct:(SKProduct *)product payments:(Payments*)payments transactionCompletedNotifier:(id<TransactionCompletedNotifier>)completedNotifier;
@end