//
//  MyClass.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>
#import "ConnectionManagerTcp.h"
#import "MediaController.h"
#import "ConnectionManagerUdp.h"
@import AVFoundation;

@interface ConnectionViewController : UIViewController<ConnectionStatusDelegateTcp, NewPacketDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, NewImageDelegate>
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *connectionProgress;
@property (weak, nonatomic) IBOutlet UILabel *theLabel;
@property (nonatomic, retain) IBOutlet UIButton * theButton;
@property (weak, nonatomic) IBOutlet UILabel *connectionStatus;
@property (weak, nonatomic) IBOutlet UITextView * textToSend;
@property OutputSessionTcp * outputSession;
@end
