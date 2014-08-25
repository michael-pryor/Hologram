//
//  MyClass.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 23/08/2014.
//
//

#import "ConnectionViewController.h"


@implementation ConnectionViewController
ConnectionManager * con;
-(void)viewDidLoad {
    [super viewDidLoad];
}
- (IBAction)onSpecialButtonClick:(id)sender {
    self.view.backgroundColor = [UIColor yellowColor];
    self.theLabel.backgroundColor = [UIColor redColor];
    self.theLabel.text = @"Wow we have changed the colours!";
}

- (IBAction)onConnectButtonClick:(id)sender {
    con = [[ConnectionManager alloc] init: self];
    [con connect];
}

- (void)connectionStatusChange:(ConnectionStatus)status withDescription:(NSString *)description {
    NSLog(@"Received status change: %u and description: %@", status, description);
    [[self connectionStatus] setText: description];
    
    switch(status) {
        case CONNECTING:
            [[self connectionStatus] setTextColor: [UIColor yellowColor]];
            [[self connectionStatus] setHidden:true];
            [[self connectionProgress] startAnimating];
            break;
            
        case OK:
            [[self connectionStatus] setTextColor: [UIColor greenColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];
            break;
        
        case ERROR:
            [[self connectionStatus] setTextColor: [UIColor redColor]];
            [[self connectionProgress] stopAnimating];
            [[self connectionStatus] setHidden:false];            
            break;
        
            
            
    }
}
@end
