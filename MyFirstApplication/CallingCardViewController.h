//
//  CallingCardViewController.h
//  Hologram
//
//  Created by Michael Pryor on 06/07/2016.
//
//

#import <UIKit/UIKit.h>

@protocol CallingCardDataProvider
- (void)setName:(NSString *)name profilePicture:(UIImage *)profilePicture callingCardText:(NSString *)callingCardText age:(uint)age distance:(uint)distance karma:(uint)karma maxKarma:(uint)maxKarma;
@end


@interface CallingCardViewController : UIViewController <CallingCardDataProvider>
@end
