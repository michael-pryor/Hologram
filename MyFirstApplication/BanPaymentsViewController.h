//
// Created by Michael Pryor on 28/06/2016.
//

#import <Foundation/Foundation.h>

#import "Payments.h"

@interface BanPaymentsViewController : UIViewController<SKPaymentTransactionObserver>
- (void)setOnFinishedFunc:(void (^)())onFinishedFunc;

- (void)setProduct:(SKProduct *)product payments:(Payments *)payments transactionCompletedNotifier:(id <TransactionCompletedNotifier>)notifier;
@end