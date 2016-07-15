//
//  CallingCardViewController.m
//  Hologram
//
//  Created by Michael Pryor on 06/07/2016.
//
//

#import "CallingCardViewController.h"
#import "Threading.h"
#import "ViewStringFormatting.h"


@implementation CallingCardViewController {
    __weak IBOutlet UIImageView *_profilePicture;
    __weak IBOutlet UILabel *_name;
    __weak IBOutlet UITextView *_text;
    __weak IBOutlet UILabel *_age;
    __weak IBOutlet UILabel *_distance;
    void(^_prepareContentsBlock)();
}
- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance karma:(uint)remoteKarmaRating maxKarma:(uint)maxKarma {
    void(^_theBlock)() = ^{
        [_profilePicture setImage:profilePicture];
        [_name setText:name];
        [_text setText:callingCardText];

        if (age == 0) {
            [_age setAlpha:0];
        } else {
            [_age setAlpha:1];
        }
        [_age setText:[NSString stringWithFormat:@"%@ years old", [ViewStringFormatting getAgeString:age]]];

        [_distance setText:[ViewStringFormatting getStringFromDistance:distance]];
    };
    if (_name == nil) {
        _prepareContentsBlock = _theBlock;
        return;
    }

    dispatch_sync_main(_theBlock);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (_prepareContentsBlock != nil) {
        _prepareContentsBlock();
        _prepareContentsBlock = nil;
    }
}

// Scroll to top on UITextViews.
- (void)viewDidLayoutSubviews {
    [_text setContentOffset:CGPointZero animated:NO];
}


@end
