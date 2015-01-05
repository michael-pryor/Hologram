//
//  MediaByteBuffer.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "MediaByteBuffer.h"

@implementation MediaByteBuffer
- (void) addImage: (CMSampleBufferRef) image {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(image);

    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    uint bytes = (uint)CVPixelBufferGetDataSize(imageBuffer);
    
    uint width = (uint)CVPixelBufferGetWidth(imageBuffer);
    uint height = (uint)CVPixelBufferGetHeight(imageBuffer);
    uint bytesPerRow = (uint)CVPixelBufferGetBytesPerRow(imageBuffer);

    [self addUnsignedInteger:bytesPerRow];
    [self addUnsignedInteger:width];
    [self addUnsignedInteger:height];
    [self addData: baseAddress withLength: bytes includingPrefix:false];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
}
- (UIImage*) getImage {
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    uint bytesPerRow = [self getUnsignedInteger];
    uint width = [self getUnsignedInteger];
    uint height = [self getUnsignedInteger];
    uint8_t * buffer = [self buffer];
    
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
