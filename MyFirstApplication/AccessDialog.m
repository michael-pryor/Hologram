//
// Created by Michael Pryor on 28/12/2015.
//

#import "AccessDialog.h"
#import "Threading.h"
#import "CoreLocation/CoreLocation.h"

@import AVFoundation;

@implementation AccessDialog {
    void (^_failureAction)(void);
}

- (id)initWithFailureAction:(void (^)(void))failureAction {
    self = [super init];
    if (self) {
        _failureAction = failureAction;
    }
    return self;
}

- (void)showFailureDialogBoxWithServiceName:(NSString *)serviceName explanation:(NSString *)subExplanation {
    // Show prior to showing dialog box so that other activities can be terminated early, prior to waiting for use to finish with dialog box.
    [self doFailureAction];

    NSString *title = [NSString stringWithFormat:@"%@%@", @"Failure to access ", serviceName];
    NSString *explanation = [NSString stringWithFormat:@"Access to %@ is restricted; please grant this application access by updating your device settings.\n\n%@.\n\nThis application cannot be used without first granting access.", serviceName, subExplanation];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:explanation delegate:self cancelButtonTitle:@"Exit" otherButtonTitles:nil, nil];
    dispatch_sync_main(^{
        [alert show];
    });
    return;
}

- (void)tryAccessCamera:(void (^)(void))successAction {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusAuthorized) {
        [AccessDialog doAction:successAction];
        return;
    } else if (authStatus == AVAuthorizationStatusNotDetermined) {
        NSLog(@"%@", @"Camera access not determined; asking for permission");

        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            [self tryAccessCamera:successAction];
        }];
    } else {
        // Failed to get access.
        [self showFailureDialogBoxWithServiceName:@"camera" explanation:@"This application facilitates video conversations with other people; for this we need to be able to access your camera so that other people can see you"];
    }
}

- (void)tryAccessMicrophone:(void (^)(void))successAction {
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        if (granted) {
            [AccessDialog doAction:successAction];
        } else {
            [self showFailureDialogBoxWithServiceName:@"microphone" explanation:@"This application facilitates video conversations with other people; for this we need to be able to access your microphone so that other people can hear you speak"];
        }
    }];
}

- (void)tryAccessGps:(void (^)(void))successAction {
    if (![CLLocationManager locationServicesEnabled]) {
        [self showFailureDialogBoxWithServiceName:@"location services" explanation:@"We attempt to match you with users who are in the same geographical region as you; for this we need access to your device's location information. Location services are currently disabled globally (for all applications) on the device"];
        return;
    }

    // If kCLAuthorizationStatusNotDetermined then we haven't yet turned on the GPS component of this app,
    // when this happens user will be asked and permission will update.
    //
    // For now we assume success.
    //
    // Note that there is no neat way of requesting it globally, as is the case with microphone and camera.
    CLAuthorizationStatus authStatus = [CLLocationManager authorizationStatus];
    if (authStatus == kCLAuthorizationStatusNotDetermined || authStatus == kCLAuthorizationStatusAuthorized || authStatus == kCLAuthorizationStatusAuthorizedAlways || authStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [AccessDialog doAction:successAction];
        return;
    } else {
        // Failed to get access.
        [self showFailureDialogBoxWithServiceName:@"location services" explanation:@"We attempt to match you with users who are in the same geographical region as you; for this we need access to your device's location information"];
    }
}

- (void)validateAuthorization:(void (^)(void))successAction {
    // Chain together access attempts: camera -> microphone -> GPS.
    [self tryAccessCamera:^{
        [self tryAccessMicrophone:^{
            [self tryAccessGps:successAction];
        }];
    }];
}

+ (void)doAction:(void (^)(void))action {
    if (action != nil) {
        action();
    }
}

- (void)doFailureAction {
    [AccessDialog doAction:_failureAction];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    NSLog(@"Prematurely terminating app due to permissions issue accessing a required resource or component");
    exit(0);
}
@end