//
// Created by Michael Pryor on 31/01/2016.
//

#import <Foundation/Foundation.h>


@interface ViewInteractions : NSObject
+ (void)fadeInOutLabel:(UILabel *)label completion:(void (^)(BOOL))block;

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration;

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration;
@end