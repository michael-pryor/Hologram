//
// Created by Michael Pryor on 28/06/2016.
//

#import <Foundation/Foundation.h>
@import StoreKit;

@protocol PaymentProductsLoadedNotifier
- (void)onPaymentProductsLoaded;
@end

@interface Payments : NSObject<SKProductsRequestDelegate>
- (id)initWithDelegate:(id <PaymentProductsLoadedNotifier>)notifier;

- (void)queryProducts;

- (SKProduct *)getKarmaProductWithMagnitude:(uint8_t)magnitude;
@end