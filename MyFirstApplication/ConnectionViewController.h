//
//  MyClass.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>
#import "ConnectionGovernorProtocol.h"
#import "VideoOutputController.h"
#import "ConnectionCommander.h"
#import "GpsState.h"
#import "SocialState.h"
#import "DnsResolver.h"
#import "ConversationEndedViewController.h"
#import "Payments.h"
#import "MatchingViewController.h"

@import AVFoundation;

@interface ConnectionViewController : UIViewController <MatchingAnswerDelegate, CallingCardDataProvider, TransactionCompletedNotifier, PaymentProductsLoadedNotifier, ConnectionStatusDelegateProtocol, NewPacketDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, NewImageDelegate, GovernorSetupProtocol, GpsStateDataLoadNotification, SocialStateDataLoadNotification, NatPunchthroughNotifier, MediaDataLossNotifier, DnsResultNotifier, ConversationRatingConsumer>
+ (void)updateKarmaUsingProgressView:(UIProgressView *)progressView ratio:(float)ratio;
@end
