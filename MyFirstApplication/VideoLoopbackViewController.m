//
// Created by Michael Pryor on 14/07/2016.
//

#import "VideoLoopbackViewController.h"
#import "Threading.h"


@implementation VideoLoopbackViewController {

    __weak IBOutlet UIImageView *_imageView;
    __weak IBOutlet UISwitch *_compressionSwitch;

    VideoOutputController *_controller;
    Signal *_compressionEnabled;
}

- (void)viewDidLoad {
    _controller = [[VideoOutputController alloc] initWithUdpNetworkOutputSession:nil imageDelegate:self mediaDataLossNotifier:nil leftPadding:sizeof(uint8_t) loopbackEnabled:true];
    _compressionEnabled = [[Signal alloc] initWithFlag:true];
}

- (void)viewDidAppear:(BOOL)animated {
    [_controller startCapturing];
}

- (void)viewDidDisappear:(BOOL)animated {
    [_controller stopCapturing];
}

- (IBAction)_onCompressionSwitchChange:(id)sender {
    if ([_compressionEnabled clear]) {
        [_controller setLocalImageDelegate:self];
    } else {
        if([_compressionEnabled signalAll]) {
            [_controller clearLocalImageDelegate];
        }
    }
}

- (void)onNewImage:(UIImage *)image {
    dispatch_sync_main(^{
        [_imageView setImage:image];
    });
}
- (IBAction)onScreenTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end