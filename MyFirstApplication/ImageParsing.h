//
// Created by Michael Pryor on 03/07/2016.
//

#import <Foundation/Foundation.h>


@interface ImageParsing : NSObject
+ (UIImage *)prepareImage:(UIImage *)image widthAndHeight:(CGFloat)widthAndHeight;

+ (NSData *)convertImageToData:(UIImage *)image;

+ (UIImage *)convertDataToImage:(NSData *)data orientation:(UIImageOrientation)orientation;
@end