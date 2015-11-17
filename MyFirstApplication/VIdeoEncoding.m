//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "VideoEncoding.h"

@implementation VideoEncoding {
    NSString *_sessionPreset;
    dispatch_queue_t _videoOutputQueue;
}
- (id)init {
    self = [super init];
    if (self) {
        _sessionPreset = AVCaptureSessionPresetLow;

        if (_sessionPreset == AVCaptureSessionPresetLow) {
            _suggestedBatchSize = 128;
        } else {
            [NSException raise:@"Invalid session preset" format:@"Session preset must be preconfigured in code"];
        }

        _videoOutputQueue = dispatch_queue_create("CameraOutputQueue", NULL);
    }
    return self;
}

// Create a UIImage from sample buffer data
- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);

    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
            bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];

    // Release the Quartz image
    CGImageRelease(quartzImage);

    return (image);
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

            // Set frame rate.
            /*if([device lockForConfiguration:NULL] == YES) {
                device.activeVideoMaxFrameDuration = CMTimeMake(1, 20);
                [device unlockForConfiguration];
            }*/

            // From the device, create an AVCaptureDeviceInput.
            // This initializes the device, the camera is now active.
            NSError *error = nil;
            input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
            if (!input) {
                NSLog(@"Could not access input device: %@", error);
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
    AVCaptureConnection *conn = [output connectionWithMediaType:AVMediaTypeVideo];
    [conn setVideoOrientation:AVCaptureVideoOrientationPortrait];

    NSArray *availableVideoCodecs = [output availableVideoCVPixelFormatTypes];
    for (NSString *codec in availableVideoCodecs) {
        NSLog(@"Codec available: %@", codec);
    }

    // Set video encoding settings.
    output.videoSettings = @{(NSString *) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};

    // Pass video output to delegate function (parameter of this method).
    [output setSampleBufferDelegate:delegate queue:_videoOutputQueue];

    return session;
}

- (void)addImage:(void *)data withLength:(uint)length toByteBuffer:(ByteBuffer *)buffer {
    [buffer addVariableLengthData:data withLength:length includingPrefix:false];
}

- (void)addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer *)buffer {
    // With compression.
    UIImage *imageObject = [self imageFromSampleBuffer:image];
    NSData *data = UIImageJPEGRepresentation(imageObject, 0.5);
    //[self addImage:(void *) [data bytes] withLength:(uint) [data length] toByteBuffer:buffer];
}


- (UIImage *)getImageFromByteBuffer:(ByteBuffer *)byteBuffer {
    uint8_t *buffer = [byteBuffer buffer] + [byteBuffer cursorPosition];
    NSData *nsData = [NSData dataWithBytes:buffer length:[byteBuffer getUnreadDataFromCursor]];
    return [UIImage imageWithData:nsData];
}
@end
