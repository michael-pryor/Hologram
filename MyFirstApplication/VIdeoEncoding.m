//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "VideoEncoding.h"
#import "VideoCompression.h"
#import "Orientation.h"
#import "VideoShared.h"

@implementation VideoEncoding {
    NSString *_sessionPreset;
    dispatch_queue_t _videoOutputQueue;

    VideoCompression *_compression;
    AVCaptureConnection *_connection;

    bool _loopbackEnabled;
}
- (id)initWithVideoCompression:(VideoCompression *)videoCompression loopbackEnabled:(bool)loopbackEnabled {
    self = [super init];
    if (self) {
        _loopbackEnabled = loopbackEnabled;

        _sessionPreset = AVCaptureSessionPreset640x480;

        _compression = videoCompression;

        _videoOutputQueue = dispatch_queue_create("CameraOutputQueue", NULL);
    }
    return self;
}

- (AVCaptureSession *)setupCaptureSessionWithDelegate:(id <AVCaptureVideoDataOutputSampleBufferDelegate>)delegate {
    // AVCaptureSession contains all information about the video input.
    //
    // An AVCaptureSession receives data from AVCaptureDeviceInput, optionally maniuplates this data
    // (e.g. compression) and then passes it to an AVCaptureDeviceOutput instance.
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = _sessionPreset; // Set the video quality.

    // Setup AVCaptureDeviceInput and load this into the session.
    {
        AVCaptureDeviceInput *input;
        {
            // Select the AVCaptureDevice, choose the front facing camera.
            AVCaptureDevice *device = nil;
            NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            for (AVCaptureDevice *d in devices) {
                if ([d position] == AVCaptureDevicePositionFront) {
                    device = d;
                    break;
                }
            }

            if (device == nil) {
                NSLog(@"No video output device found matching specification, defaulting to first in list");
                device = devices[0];
            }

            if (device == nil) {
                NSLog(@"No video output devices found");
                return nil;
            }

            // From the device, create an AVCaptureDeviceInput.
            // This initializes the device, the camera is now active.
            NSError *error = nil;
            input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
            if (!input) {
                NSLog(@"Could not access input device: %@", error);
                return nil;
            }
        }

        // Load the chosen AVCaptureDeviceInput into the AVCaptureSession
        [session addInput:input];
    }


    // Setup AVCaptureVideoDataOutput
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];

    // Load AVCaptureVideoDataOutput into AVCaptureSession
    [session addOutput:output];

    // Set video orientation and frame rate.
    _connection = [output connectionWithMediaType:AVMediaTypeVideo];
    //[conn setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
    [_connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    NSArray *availableVideoCodecs = [output availableVideoCVPixelFormatTypes];
    for (NSString *codec in availableVideoCodecs) {
        NSLog(@"Codec available: %@", codec);
    }

    // Set video encoding settings.
    output.videoSettings = @{(NSString *) kCVPixelBufferPixelFormatTypeKey : @(getVideoEncodingTypeOs())};

    // Pass video output to delegate function (parameter of this method).
    [output setSampleBufferDelegate:delegate queue:_videoOutputQueue];

    [Orientation registerForOrientationChangeNotificationsWithObject:self selector:@selector(onOrientationChange:)];
    [self onOrientationChange:nil];

    return session;
}

- (void)onOrientationChange:(NSNotification *)notification {
    UIInterfaceOrientation orientation = [Orientation getDeviceOrientation];
    AVCaptureVideoOrientation videoOrientation;

    switch(orientation) {
        case UIInterfaceOrientationLandscapeRight:
        case UIInterfaceOrientationPortraitUpsideDown:
            videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;

        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationPortrait:
        case UIInterfaceOrientationUnknown:
        default:
            videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
    }

    [_connection setVideoOrientation:videoOrientation];
}

- (bool)addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer *)buffer {
    // Can only have one user of encoder, loopback is happening directly in compression module.
    if (_loopbackEnabled) {
        return nil;
    }

    return [_compression encodeSampleBuffer:(CMSampleBufferRef) image toByteBuffer:buffer];
}


- (UIImage *)getImageFromByteBuffer:(ByteBuffer *)byteBuffer {
    // Can only have one user of encoder, loopback is happening directly in compression module.
    if (_loopbackEnabled) {
        return nil;
    }

    return [_compression decodeByteBuffer:byteBuffer];
}

- (UIImage *)convertSampleBufferToUiImage:(CMSampleBufferRef)sampleBuffer {
    // No actual compression/decompression here, but reusing some of the same logic.
    // Exception to this rule is if loopback is enabled.
    return [_compression convertSampleBufferToUiImage:sampleBuffer];
}
@end
