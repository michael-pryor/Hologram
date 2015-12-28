//
// Created by Michael Pryor on 28/12/2015.
//

#import <Foundation/Foundation.h>

/**
 * Class aimed at verifying relevant access has been granted, and showing dialog boxes if not.
 */
@interface AccessDialog : NSObject<UIAlertViewDelegate>
- (id)initWithFailureAction:(void (^)(void))failureAction;
- (void)validateAuthorization:(void (^)(void))successAction;
@end