//
//  AlertViewController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/09/2015.
//
//

@import iAd;
#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>

@interface AlertViewController : UIViewController
- (void)setAlertShortText:(NSString*)shortText longText:(NSString*)longText;
-(Boolean)hideIfVisibleAndReady;
@end
