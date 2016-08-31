//
// Created by Michael Pryor on 31/01/2016.
//

#import <Foundation/Foundation.h>

// Alpha of a button just after it has been pressed.
#define ALPHA_BUTTON_PRESSED 0.1f

// Some image buttons look better with some alpha by defalut.
#define ALPHA_BUTTON_IMAGE_READY 0.6f

#define ALPHA_BUTTON_READY 1

@interface ViewInteractions : NSObject
+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block options:(UIViewAnimationOptions)options;

+ (void)fadeInOut:(UIView *)label completion:(void (^)(BOOL))block;

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration;

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration;

+ (void)fadeInOut:(UIView *)entity completion:(void (^)(BOOL))block options:(UIViewAnimationOptions)options fadeInDuration:(float)durationIn fadeOutDuration:(float)durationOut fadeOutDelay:(float)delay;

+ (void)fadeOut:(UIView*)viewA thenIn:(UIView*)viewB duration:(float)duration;

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha options:(UIViewAnimationOptions)options;

+ (void)fadeOut:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha;

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha options:(UIViewAnimationOptions)options;

+ (void)fadeIn:(UIView *)label completion:(void (^)(BOOL))block duration:(float)duration toAlpha:(float)alpha;
@end