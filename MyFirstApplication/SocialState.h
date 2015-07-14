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

@interface SocialState : NSObject
@property (readonly) Boolean isDataLoaded;
@property (readonly) NSString* firstName;
@property (readonly) NSString* middleName;
@property (readonly) NSString* lastName;
@property (readonly) NSURL* facebookUrl;
@property (readonly) NSString* facebookId;

@property (readonly) NSString* humanFullName;
@property (readonly) NSString* humanShortName;

@property (readonly) NSString* gender;
@property (readonly) NSString* dob;
@property (readonly) uint age;
@property (readonly) uint genderI;
@property (readonly) uint interestedInI;
@property (readonly) NSString* interestedIn;

+(SocialState*)getFacebookInstance;
-(void)reset;
-(void)updateFacebook;
-(void)update;


@end
