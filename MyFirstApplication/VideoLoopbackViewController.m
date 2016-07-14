//
// Created by Michael Pryor on 14/07/2016.
//

#import "VideoLoopbackViewController.h"
#import "Threading.h"


@implementation VideoLoopbackViewController {

    __weak IBOutlet UIImageView *_imageView;
    __weak IBOutlet UISwitch *_compressionSwitch;

    VideoOutputController *_controller;
}

- (void)viewDidLoad {
    self.screenName = @"VideoLoopback";

    _controller = [[VideoOutputController alloc] initWithUdpNetworkOutputSession:nil imageDelegate:self mediaDataLossNotifier:nil leftPadding:sizeof(uint8_t) loopbackEnabled:true];
    [_controller setVideoDelayMs:0];
}

- (void)viewDidAppear:(BOOL)animated {
    [_controller startCapturing];
}

- (void)viewDidDisappear:(BOOL)animated {
    [_controller stopCapturing];
}

- (IBAction)_onCompressionSwitchChange:(id)sender {
    if (![_compressionSwitch isOn]) {
        [_controller setLocalImageDelegate:self];
        [_controller resetInbound];
    } else {
        [_controller resetInbound];
        [_controller clearLocalImageDelegate];
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