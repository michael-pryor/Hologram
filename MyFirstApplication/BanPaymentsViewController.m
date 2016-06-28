//
// Created by Michael Pryor on 28/06/2016.
//

#import "BanPaymentsViewController.h"


@implementation BanPaymentsViewController {
    void(^_onFinishedFunc)();
}
- (void)setOnFinishedFunc:(void (^)())onFinishedFunc {
    _onFinishedFunc = onFinishedFunc;
}
- (IBAction)onTap:(id)sender {
    _onFinishedFunc();
}

@end