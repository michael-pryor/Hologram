//
// Created by Michael Pryor on 28/06/2016.
//

#import <StoreKit/StoreKit.h>
#import "BanPaymentsViewController.h"
#import "Threading.h"
#import "Signal.h"


@implementation BanPaymentsViewController {
    void(^_onFinishedFunc)();

    SKProduct *_product;
    Payments *_payments;
    __weak IBOutlet UILabel *_price;

    Signal *_paymentInProgress;
    id<TransactionCompletedNotifier> _completedNotifier;
}
- (void)viewDidLoad {
    _paymentInProgress = [[Signal alloc] initWithFlag:false];

}

- (void)setOnFinishedFunc:(void (^)())onFinishedFunc {
    _onFinishedFunc = onFinishedFunc;
}

- (IBAction)onTap:(id)sender {
    if ([_paymentInProgress isSignaled]) {
        return;
    }
    _onFinishedFunc();
}

- (void)setProduct:(SKProduct *)product payments:(Payments *)payments transactionCompletedNotifier:(id <TransactionCompletedNotifier>)notifier {
    _product = product;
    _payments = payments;
    _completedNotifier = notifier;
    dispatch_sync_main(^{
        [_price setText:[Payments getPriceOfProduct:_product]];
    });
    
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)viewWillDisappear:(BOOL)animated {
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (void)dealloc {
    NSLog(@"Deallocing");
}

- (IBAction)onPurchasePress:(id)sender {
    if (![_paymentInProgress signalAll]) {
        return;
    }

    [_payments payForProduct:_product];
}

- (void)onPurchaseFailure:(SKPaymentTransaction*)transaction {
    NSLog(@"Purchase failed");
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    [_paymentInProgress clear];
}

- (void)onPurchaseSuccess:(SKPaymentTransaction*)transaction {
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receipt = [NSData dataWithContentsOfURL:receiptURL];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    if (receipt != nil) {
        NSLog(@"Successfully purchased karma regeneration");
        [_completedNotifier onTransactionCompleted:receipt];
    } else {
        NSLog(@"Successfully purchased karma regeneration, but failed to validate receipt");
        [self onPurchaseFailure:transaction];
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            // Call the appropriate custom method for the transaction state.
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"Started performing purchase action");
                if ([transaction originalTransaction] != nil) {
                    NSLog(@"There's something here");
                }
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"Purchase action is queued and will be performed soon");
                break;
            case SKPaymentTransactionStateFailed:
                [self onPurchaseFailure:transaction];
                break;
            case SKPaymentTransactionStatePurchased:
                [self onPurchaseSuccess:transaction];
                break;
            case SKPaymentTransactionStateRestored:
                NSLog(@"Restored transaction");
                [self onPurchaseSuccess:[transaction originalTransaction]];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            default:
                // For debugging
                NSLog(@"Unexpected transaction state %@", @(transaction.transactionState));
                break;
        }
    }
}

@end