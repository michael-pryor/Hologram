//
//  CallingCardViewController.h
//  Hologram
//
//  Created by Michael Pryor on 06/07/2016.
//
//

#import <UIKit/UIKit.h>

@protocol CallingCardDataProvider
- (void)setName:(NSString *)name text:(NSString *)text profilePicture:(UIImage *)profilePicture;
@end


@interface CallingCardViewController : UIViewController<CallingCardDataProvider>
@end
