//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "VideoEncoding.h"

@implementation VideoEncoding {
    NSString * _sessionPreset;
}
- (id) init {
    self = [super init];
    if(self) {
        _sessionPreset = AVCaptureSessionPresetLow;
        
        if(_sessionPreset == AVCaptureSessionPresetLow) {
            _bytesPerRow = 576;
            _height = 192;
            _totalSize = _bytesPerRow * _height;
            
            _suggestedBatchSize = _bytesPerRow * 2;
            _suggestedBatches = _height / 2;
        } else {
            [NSException raise:@"Invalid session preset" format:@"Session preset must be preconfigured in code"];
        }
    }
    return self;
}

// Create a UIImage from sample buffer data
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
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
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
}

- (AVCaptureSession *) setupCaptureSessionWithDelegate: (id<AVCaptureVideoDataOutputSampleBufferDelegate>) delegate {
    AVCaptureSession* session = [[AVCaptureSession alloc] init];
    
    session.sessionPreset = _sessionPreset;
    
    // access input device.
    AVCaptureDevice *device;
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for(AVCaptureDevice* d in devices) {
        if([d position] == AVCaptureDevicePositionFront) {
            device = d;
            break;
        }
    }
    
    
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        NSLog(@"Could not access input device: %@", error);
    }
    
    // add input device to session.
    [session addInput:input];
    
    // setup output session.
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    [session addOutput:output];
    
    AVCaptureConnection *conn = [output connectionWithMediaType:AVMediaTypeVideo];
    [conn setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    conn.videoMinFrameDuration = CMTimeMake(1, 20);
    
    output.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    
    dispatch_queue_t queue = dispatch_queue_create("CameraOutputQueue", NULL);
    
    // tell output session to use newly created queue, and push to captureOutput function.
    [output setSampleBufferDelegate:delegate queue:queue];
    
    return session;
}

- (void) addImage:(CMSampleBufferRef)image toByteBuffer:(ByteBuffer*)buffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(image);
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    uint bytes = (uint)CVPixelBufferGetDataSize(imageBuffer);
    uint width = (uint)CVPixelBufferGetWidth(imageBuffer);

    uint height = (uint)CVPixelBufferGetHeight(imageBuffer);
    uint bytesPerRow = (uint)CVPixelBufferGetBytesPerRow(imageBuffer);
    
    [buffer addVariableLengthData: baseAddress withLength: bytesPerRow * height includingPrefix:false];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
}

- (UIImage*) getImageFromByteBuffer:(ByteBuffer*)byteBuffer {
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    uint bytesPerRow = 576;//[_buffer getUnsignedInteger];
    uint width = 144;//[_buffer getUnsignedInteger];
    uint height = 192;//[_buffer getUnsignedInteger];
    
    
    uint8_t * buffer = [byteBuffer buffer] + [byteBuffer cursorPosition];
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return image;
}
@end