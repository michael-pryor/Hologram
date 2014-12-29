//
//  MyClass.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>
#import "ConnectionManager.h"

@interface ConnectionViewController : UIViewController<ConnectionStatusDelegate, NewPacketDelegate, UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *connectionProgress;
@property (weak, nonatomic) IBOutlet UILabel *theLabel;
@property (nonatomic, retain) IBOutlet UIButton * theButton;
@property (weak, nonatomic) IBOutlet UILabel *connectionStatus;
@property (weak, nonatomic) IBOutlet UITextView * textToSend;
@property OutputSession * outputSession;
@end
