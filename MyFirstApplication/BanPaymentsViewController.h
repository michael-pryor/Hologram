//
// Created by Michael Pryor on 28/06/2016.
//

#import <Foundation/Foundation.h>


@interface BanPaymentsViewController : UIViewController
- (void)setOnFinishedFunc:(void (^)())onFinishedFunc;
@end