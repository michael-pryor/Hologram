//
// Created by Michael Pryor on 31/01/2016.
//

#import <Foundation/Foundation.h>


@interface ViewInteractions : NSObject
+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block options:(UIViewAnimationOptions)options;

+ (void)fadeInOut:(UIView *)label completion:(void (^)(BOOL))block;

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration;

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration;

+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block options:(UIViewAnimationOptions)options fadeInDuration:(float)durationIn fadeOutDuration:(float)durationOut fadeOutDelay:(float)delay;
@end