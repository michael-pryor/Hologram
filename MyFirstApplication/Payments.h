//
// Created by Michael Pryor on 28/06/2016.
//

#import <Foundation/Foundation.h>
@import StoreKit;

@protocol PaymentProductsLoadedNotifier
- (void)onPaymentProductsLoaded;
@end

@protocol TransactionCompletedNotifier
- (void)onTransactionCompleted:(NSData*)data;
@end

@interface Payments : NSObject <SKProductsRequestDelegate>
- (id)initWithDelegate:(id <PaymentProductsLoadedNotifier>)notifier;

- (void)queryProducts:(NSString*)userAccountId;

- (SKProduct *)getKarmaProductWithMagnitude:(uint8_t)magnitude;

+ (NSString *)getPriceOfProduct:(SKProduct *)product;

- (void)payForProduct:(SKProduct*)product;
@end