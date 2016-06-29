//
// Created by Michael Pryor on 28/06/2016.
//

#import <StoreKit/StoreKit.h>
#import "BanPaymentsViewController.h"
#import "Payments.h"
#import "Threading.h"


@implementation BanPaymentsViewController {
    void(^_onFinishedFunc)();

    SKProduct *_product;
    __weak IBOutlet UILabel *_price;
}
- (void)viewDidLoad {

}

- (void)setOnFinishedFunc:(void (^)())onFinishedFunc {
    _onFinishedFunc = onFinishedFunc;
}

- (IBAction)onTap:(id)sender {
    _onFinishedFunc();
}

- (void)setProduct:(SKProduct *)product {
    _product = product;
    dispatch_sync_main(^ {
        [_price setText:[Payments getPriceOfProduct:_product]];
    });
}
- (IBAction)onPurchasePress:(id)sender {
}
@end