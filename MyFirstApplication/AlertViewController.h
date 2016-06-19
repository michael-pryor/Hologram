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
#import <FBAudienceNetwork/FBAudienceNetwork.h>
#import "VideoOutputController.h"

@interface AlertViewController : UIViewController<FBAdViewDelegate, NewImageDelegate>
- (void)setAlertShortText:(NSString *)shortText;

- (Boolean)hideIfVisibleAndReady;

- (void)hideNow;

- (NSString*)getScreenName;

- (void)setMoveToFacebookViewControllerFunc:(void(^)())moveToFacebookViewControllerFunc;

- (void)enableAdverts;

- (void)setConversationEndedViewVisible:(bool)visible instantly:(bool)instant;
@end
