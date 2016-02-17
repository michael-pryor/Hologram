//
//  SocialState.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import <Foundation/Foundation.h>

#define MALE 1
#define FEMALE 2
#define BOTH 3

extern const NSString* selectedGenderPreferenceKey;

@class SocialState;
@protocol SocialStateDataLoadNotification <NSObject>
- (void)onSocialDataLoaded:(SocialState *)state;
@end

@interface SocialState : NSObject
@property(readonly) Boolean isBasicDataLoaded;
@property(readonly) Boolean isGraphDataLoaded;
@property(readonly) NSString *firstName;
@property(readonly) NSString *middleName;
@property(readonly) NSString *lastName;
@property(readonly) NSURL *facebookUrl;
@property(readonly) NSString *facebookId;

@property(readonly) NSString *humanFullName;
@property(readonly) NSString *humanShortName;

@property(readonly) NSString *gender;
@property(readonly) NSString *dob;
@property(readonly) uint age;
@property(readonly) uint genderI;
@property(readonly) uint interestedIn;

// This relates to the Facebook login view, the index of the selected button.
// Used to rebuild this during initialization.
@property(readonly) int interestedInSegmentIndex;

- (void)reset;

- (void)updateCoreFacebookInformation;

- (bool)updateGraphFacebookInformation;

- (void)update;

- (void)setInterestedInWithSegmentIndex:(int)segmentIndex;

+ (SocialState *)getFacebookInstance;

- (void)registerNotifier:(id <SocialStateDataLoadNotification>)notifier;

- (void)unregisterNotifier;

- (Boolean)isDataLoaded;

- (void)setInterestedIn:(NSString *)interestedIn;
@end

