//
// Created by Michael Pryor on 28/06/2016.
//

#import "Payments.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation Payments {
    SKProductsRequest *_productsRequest;
    NSArray<SKProduct *> *_products;
    id <PaymentProductsLoadedNotifier> _notifier;

    NSArray *_productIds;
    NSString *_hashedAccountId;

}
- (id)initWithDelegate:(id <PaymentProductsLoadedNotifier>)notifier {
    self = [super init];
    if (self) {
        _notifier = notifier;
        _hashedAccountId = nil;
        _productIds = @[@"karma_1", @"karma_2", @"karma_3"];
    }
    return self;
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    _products = response.products;

    for (NSString *invalidIdentifier in response.invalidProductIdentifiers) {
        NSLog(@"ERROR: Invalid identifier received from Apple in app payments: %@", invalidIdentifier);
    }

    [_notifier onPaymentProductsLoaded];
}

- (void)queryProducts:(NSString*)userAccountId {
    if (_products != nil && [_products count] > 0) {
        [_notifier onPaymentProductsLoaded];
        return;
    }

    if (userAccountId != nil) {
        _hashedAccountId = [Payments hashedValueForAccountName:userAccountId];
    }

    _productsRequest = [[SKProductsRequest alloc]
            initWithProductIdentifiers:[NSSet setWithArray:_productIds]];

    // Keep a strong reference to the request.
    _productsRequest.delegate = self;
    [_productsRequest start];
}

- (SKProduct *)getKarmaProductWithMagnitude:(uint8_t)magnitude {
    NSString *_productId = [NSString stringWithFormat:@"karma_%d", magnitude];
    for (NSUInteger n = 0; n < _products.count; n++) {
        if ([_productId isEqualToString:_products[n].productIdentifier]) {
            return _products[n];
        }
    }
    return nil;
}

+ (NSString *)getPriceOfProduct:(SKProduct *)product {
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [numberFormatter setLocale:product.priceLocale];
    NSString *formattedPrice = [numberFormatter stringFromNumber:product.price];
    return formattedPrice;
}

// Custom method to calculate the SHA-256 hash using Common Crypto
+ (NSString *)hashedValueForAccountName:(NSString*)userAccountName {
    const int HASH_SIZE = 32;
    unsigned char hashedChars[HASH_SIZE];
    const char *accountName = [userAccountName UTF8String];
    size_t accountNameLen = strlen(accountName);
    
    // Confirm that the length of the user name is small enough
    // to be recast when calling the hash function.
    if (accountNameLen > UINT32_MAX) {
        NSLog(@"Account name too long to hash: %@", userAccountName);
        return nil;
    }
    CC_SHA256(accountName, (CC_LONG)accountNameLen, hashedChars);
    
    // Convert the array of bytes into a string showing its hex representation.
    NSMutableString *userAccountHash = [[NSMutableString alloc] init];
    for (int i = 0; i < HASH_SIZE; i++) {
        // Add a dash every four bytes, for readability.
        if (i != 0 && i%4 == 0) {
            [userAccountHash appendString:@"-"];
        }
        [userAccountHash appendFormat:@"%02x", hashedChars[i]];
    }
    
    return userAccountHash;
}

- (void)payForProduct:(SKProduct*)product {
    SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
    payment.quantity = 1;

    if (_hashedAccountId != nil) {
        payment.applicationUsername = _hashedAccountId;
    }

    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

@end