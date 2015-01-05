//
//  MediaByteBuffer.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "MediaByteBuffer.h"

@implementation MediaByteBuffer {
    ByteBuffer * _buffer;
}
- (id) initFromBuffer: (ByteBuffer*)byteBuffer {
    self = [super init];
    if(self) {
        _buffer = byteBuffer;
    }
    return self;
}

- (void) addImage: (CMSampleBufferRef) image {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(image);

    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    uint bytes = (uint)CVPixelBufferGetDataSize(imageBuffer);
    
    uint width = (uint)CVPixelBufferGetWidth(imageBuffer);
    uint height = (uint)CVPixelBufferGetHeight(imageBuffer);
    uint bytesPerRow = (uint)CVPixelBufferGetBytesPerRow(imageBuffer);

    [_buffer addUnsignedInteger:bytesPerRow];
    [_buffer addUnsignedInteger:width];
    [_buffer addUnsignedInteger:height];
    [_buffer addData: baseAddress withLength: bytes includingPrefix:false];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
}
- (UIImage*) getImage {
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    uint bytesPerRow = [_buffer getUnsignedInteger];
    uint width = [_buffer getUnsignedInteger];
    uint height = [_buffer getUnsignedInteger];
    uint8_t * buffer = [_buffer buffer] + [_buffer cursorPosition];
    
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