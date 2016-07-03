//
//  SocialState.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import <Foundation/Foundation.h>


extern const NSString* selectedGenderPreferenceKey;
extern const NSString* ownerGenderKey;

@class SocialState;
@protocol SocialStateDataLoadNotification <NSObject>
- (void)onSocialDataLoaded:(SocialState *)state;
@end

@interface SocialState : NSObject
@property(readonly) Boolean isBasicDataLoaded;
@property(readonly) Boolean isGraphDataLoaded;
@property(readonly) NSString *persistedUniqueId;

@property(readonly) NSString *humanFullName;
@property(readonly) NSString *humanShortName;

@property(readonly) NSString *genderString;
@property(readonly) NSString *dobString;
@property(readonly) NSDate *dobObject;
@property(readonly) uint age;
@property(readonly) uint genderEnum;
@property(readonly) uint interestedIn;

@property(readonly) UIImage* profilePictureImage;

// This relates to the Facebook login view, the index of the selected button.
// Used to rebuild this during initialization.
@property(readonly) int interestedInSegmentIndex;
@property(readonly) int genderSegmentIndex;

- (bool)updateFromFacebookCore;

- (bool)updateFromFacebookGraph;

- (void)persistInterestedInWithSegmentIndex:(int)segmentIndex;

+ (SocialState *)getSocialInstance;

- (void)registerNotifier:(id <SocialStateDataLoadNotification>)notifier;

- (void)unregisterNotifier;

- (bool)isDataLoaded;

- (void)persistOwnerGenderWithSegmentIndex:(int)segmentIndex;

- (void)persistHumanFullName:(NSString*)humanFullName humanShortName:(NSString*)humanShortName;

- (void)persistDateOfBirthObject:(NSDate*)dateOfBirth;

- (void)persistProfilePictureImage:(UIImage *)image;
@end

