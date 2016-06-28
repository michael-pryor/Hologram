//
// Created by Michael Pryor on 28/06/2016.
//

#import "Payments.h"


@implementation Payments {
    SKProductsRequest *_productsRequest;
    NSArray<SKProduct *> *_products;
    id <PaymentProductsLoadedNotifier> _notifier;

    NSArray *_productIds;
}
- (id)initWithDelegate:(id <PaymentProductsLoadedNotifier>)notifier {
    self = [super init];
    if (self) {
        _notifier = notifier;

        _productIds = @[@"karma_1"];
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

- (void)queryProducts {
    _productsRequest = [[SKProductsRequest alloc]
            initWithProductIdentifiers:[NSSet setWithArray:_productIds]];

    // Keep a strong reference to the request.
    _productsRequest.delegate = self;
    [_productsRequest start];
}

- (SKProduct *)getKarmaProductWithMagnitude:(uint8_t)magnitude {
    NSString* _productId = [NSString stringWithFormat:@"karma_%d", magnitude];
    for (NSUInteger n = 0; n<_products.count; n++) {
        if ([_productId isEqualToString:_products[n].productIdentifier]) {
            return _products[n];
        }
    }
    return nil;
}
@end