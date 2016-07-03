//
// Created by Michael Pryor on 03/07/2016.
//

#import "ImageParsing.h"


@implementation ImageParsing {

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

+ (UIImage *)prepareImage:(UIImage *)image widthAndHeight:(CGFloat)widthAndHeight {
    UIImage *cropped = [self cropImageToSquare:image];
    NSLog(@"Cropped profile picture width: %.2f, height: %.2f", [cropped size].width, [cropped size].height);
    UIImage *resized = [self resizeImage:cropped width:widthAndHeight height:widthAndHeight];
    NSLog(@"Size optimized profile picture width: %.2f, height: %.2f", [resized size].width, [resized size].height);

    // Some compression takes place here, so best to go all the way.
    UIImage * result = [self convertDataToImage:[self convertImageToData:resized] orientation:[image imageOrientation]];
    NSLog(@"Compressed profile picture width: %.2f, height: %.2f", [result size].width, [result size].height);

    return result;
}

+ (UIImage *)convertDataToImage:(NSData *)data orientation:(UIImageOrientation)orientation {
    UIImage *image = [UIImage imageWithData:data];
    return [[UIImage alloc] initWithCGImage:[image CGImage] scale:1.0 orientation:orientation];
}

+ (NSData *)convertImageToData:(UIImage *)image {
    if (image == nil) {
        return nil;
    }

    return UIImageJPEGRepresentation(image, 0.6f);
}
@end