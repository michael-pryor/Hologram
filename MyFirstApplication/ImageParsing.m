//
// Created by Michael Pryor on 03/07/2016.
//

#import "ImageParsing.h"

#define IMAGE_ORIENT_UP 1
#define IMAGE_ORIENT_DOWN 2
#define IMAGE_ORIENT_LEFT 3
#define IMAGE_ORIENT_RIGHT 4
#define IMAGE_ORIENT_UP_MIRRORED 5
#define IMAGE_ORIENT_DOWN_MIRRORED 6
#define IMAGE_ORIENT_LEFT_MIRRORED 7
#define IMAGE_ORIENT_RIGHT_MIRRORED 8

@implementation ImageParsing {

}
+ (CGFloat)getDefaultWidthAndHeight {
    return 200;
}

+ (UIImage *)resizeImage:(UIImage *)image width:(CGFloat)width height:(CGFloat)height {
    // Resize the image to save on size.
    CGSize imageSize;
    imageSize.height = height;
    imageSize.width = width;
    UIGraphicsBeginImageContext(imageSize);
    [image drawInRect:CGRectMake(0, 0, imageSize.width, imageSize.height)];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)cropImageToSquare:(UIImage *)image {
    // Need in pixels (which CGImageGet returns), not in points.
    CGFloat imageFullWidth = CGImageGetWidth([image CGImage]);
    CGFloat imageFullHeight = CGImageGetHeight([image CGImage]);

    CGFloat desiredHeight;
    CGFloat desiredWidth;

    if (imageFullHeight > imageFullWidth) {
        desiredHeight = imageFullWidth;
        desiredWidth = imageFullWidth;
    } else {
        desiredHeight = imageFullHeight;
        desiredWidth = imageFullHeight;
    }

    CGFloat desiredHeightDiff = imageFullHeight - desiredHeight;
    CGFloat desiredWidthDiff = imageFullWidth - desiredWidth;

    CGFloat originX = desiredWidthDiff / 2.0f;
    CGFloat originY = desiredHeightDiff / 2.0f;

    // Resize the image to save on size.
    CGRect imageSize;
    imageSize.size.height = desiredHeight;
    imageSize.size.width = desiredWidth;
    imageSize.origin.x = originX;
    imageSize.origin.y = originY;
    CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], imageSize);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef];
    return cropped;
}

+ (UIImage *)prepareImage:(UIImage *)image {
    return [self prepareImage:image widthAndHeight:[self getDefaultWidthAndHeight]];
}

+ (UIImage *)prepareImage:(UIImage *)image widthAndHeight:(CGFloat)widthAndHeight {
    UIImage *cropped = [self cropImageToSquare:image];
    NSLog(@"Cropped profile picture width: %.2f, height: %.2f", [cropped size].width, [cropped size].height);
    UIImage *resized = [self resizeImage:cropped width:widthAndHeight height:widthAndHeight];
    NSLog(@"Size optimized profile picture width: %.2f, height: %.2f", [resized size].width, [resized size].height);

    // Some compression takes place here, so best to go all the way.
    UIImage *result = [self convertDataToImage:[self convertImageToData:resized] orientation:[image imageOrientation]];
    NSLog(@"Compressed profile picture width: %.2f, height: %.2f", [result size].width, [result size].height);

    return result;
}

+ (UIImage *)convertDataToImage:(NSData *)data orientation:(UIImageOrientation)orientation {
    if (data == nil) {
        return nil;
    }

    UIImage *image = [UIImage imageWithData:data];
    return [[UIImage alloc] initWithCGImage:[image CGImage] scale:1.0 orientation:orientation];
}


/*
 typedef NS_ENUM(NSInteger, UIImageOrientation) {
    UIImageOrientationUp,            // default orientation
    UIImageOrientationDown,          // 180 deg rotation
    UIImageOrientationLeft,          // 90 deg CCW
    UIImageOrientationRight,         // 90 deg CW
    UIImageOrientationUpMirrored,    // as above but image mirrored along other axis. horizontal flip
    UIImageOrientationDownMirrored,  // horizontal flip
    UIImageOrientationLeftMirrored,  // vertical flip
    UIImageOrientationRightMirrored, // vertical flip
};
 */


+ (uint)parseOrientationToInteger:(UIImageOrientation)orientation {
    switch(orientation) {
        case (UIImageOrientationUp):
            return IMAGE_ORIENT_UP;

        case (UIImageOrientationDown):
            return IMAGE_ORIENT_DOWN;

        case (UIImageOrientationLeft):
            return IMAGE_ORIENT_LEFT;

        case (UIImageOrientationRight):
            return IMAGE_ORIENT_RIGHT;

        case (UIImageOrientationUpMirrored):
            return IMAGE_ORIENT_UP_MIRRORED;

        case (UIImageOrientationDownMirrored):
            return IMAGE_ORIENT_DOWN_MIRRORED;

        case (UIImageOrientationLeftMirrored):
            return IMAGE_ORIENT_LEFT_MIRRORED;

        case (UIImageOrientationRightMirrored):
            return IMAGE_ORIENT_RIGHT_MIRRORED;

        default:
            NSLog(@"Failed to process enum UIImageOrientation, defaulting to UP");
            return IMAGE_ORIENT_UP;
    }
}

+ (UIImageOrientation)parseIntegerToOrientation:(uint)orientation {
    switch(orientation) {
        case (IMAGE_ORIENT_UP):
            return UIImageOrientationUp;

        case (IMAGE_ORIENT_DOWN):
            return UIImageOrientationDown;

        case (IMAGE_ORIENT_LEFT):
            return UIImageOrientationLeft;

        case (IMAGE_ORIENT_RIGHT):
            return UIImageOrientationRight;

        case (IMAGE_ORIENT_UP_MIRRORED):
            return UIImageOrientationUpMirrored;

        case (IMAGE_ORIENT_DOWN_MIRRORED):
            return UIImageOrientationDownMirrored;

        case (IMAGE_ORIENT_LEFT_MIRRORED):
            return UIImageOrientationLeftMirrored;

        case (IMAGE_ORIENT_RIGHT_MIRRORED):
            return UIImageOrientationRightMirrored;

        default:
            NSLog(@"Failed to process integer UIImageOrientation, defaulting to UP");
            return UIImageOrientationUp;
    }
}

+ (NSData *)convertImageToData:(UIImage *)image {
    if (image == nil) {
        return nil;
    }

    return UIImageJPEGRepresentation(image, 0.6f);
}

+ (UIImage *)convertDataToImage:(NSData *)data {
    return [self convertDataToImage:data orientation:UIImageOrientationUp];
}
@end