//
//  NatPunchthroughViewController.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 16/05/2015.
//
//

#import <Foundation/Foundation.h>
#import "ConnectionManagerProtocol.h"

@interface NatPunchthroughViewController : UIViewController<NewPacketDelegate, ConnectionStatusDelegateProtocol>
@property (weak, nonatomic) IBOutlet UILabel *connectionStatus;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *connectionProgress;
@end
