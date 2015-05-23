//
//  MyClass.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>
#import "ConnectionManagerProtocol.h"
#import "MediaController.h"
@import AVFoundation;

@interface ConnectionViewController : UIViewController<ConnectionStatusDelegateProtocol, NewPacketDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, NewImageDelegate>
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *connectionProgress;
@property (weak, nonatomic) IBOutlet UILabel *connectionStatus;
@end
