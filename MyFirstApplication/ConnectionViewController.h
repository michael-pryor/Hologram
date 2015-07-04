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
@import AVFoundation;

@interface ConnectionViewController : UIViewController<ConnectionStatusDelegateProtocol, NewPacketDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, NewImageDelegate, VideoSpeedNotifier, SlowNetworkDelegate, GovernorSetupProtocol>
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *connectionProgress;
@property (weak, nonatomic) IBOutlet UILabel *connectionStatus;
@end
