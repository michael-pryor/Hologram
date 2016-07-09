//
//  SocialState.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import <Foundation/Foundation.h>

// Users must be > 18 years old to use this application.
#define MINIMUM_AGE 18

@class SocialState;
@protocol SocialStateDataLoadNotification <NSObject>
- (void)onSocialDataLoaded:(SocialState *)state;
@end

@interface SocialState : NSObject
@property(readonly) NSString *humanFullName;
@property(readonly) NSString *humanShortName;

@property(readonly) NSString *callingCardText;

@property(readonly) NSString *genderString;
@property(readonly) NSString *dobString;
@property(readonly) NSDate *dobObject;
@property(readonly) uint age;
@property(readonly) uint genderEnum;
@property(readonly) uint interestedIn;

@property(readonly) UIImage* profilePictureImage;
@property(readonly) UIImageOrientation profilePictureOrientation;
@property(readonly) uint profilePictureOrientationInteger;
@property(readonly) NSData* profilePictureData;

// This relates to the Facebook login view, the index of the selected button.
// Used to rebuild this during initialization.
@property(readonly) int interestedInSegmentIndex;
@property(readonly) int genderSegmentIndex;

@property(readonly) bool hasAcceptedEula;

- (bool)updateFromFacebookCore;

- (bool)updateFromFacebookGraph;

- (void)persistInterestedInWithSegmentIndex:(int)segmentIndex;

+ (SocialState *)getSocialInstance;

- (void)registerNotifier:(id <SocialStateDataLoadNotification>)notifier;

- (bool)isDataLoaded;

- (bool)isDataLoadedAndEulaAccepted;

- (void)persistOwnerGenderWithSegmentIndex:(int)segmentIndex;

- (void)persistHumanFullName:(NSString*)humanFullName humanShortName:(NSString*)humanShortName;

- (void)persistDateOfBirthObject:(NSDate*)dateOfBirth;

- (void)persistProfilePictureImage:(UIImage *)image;

- (void)persistCallingCardText:(NSString *)text;

- (void)persistHasAcceptedEula;
@end

