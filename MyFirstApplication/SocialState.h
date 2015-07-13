//
//  SocialState.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import <Foundation/Foundation.h>

@interface SocialState : NSObject
@property Boolean isDataLoaded;
@property NSString* firstName;
@property NSString* middleName;
@property NSString* lastName;
@property NSURL* facebookUrl;
@property NSString* facebookId;

@property NSString* humanFullName;
@property NSString* humanShortName;

@property NSString* gender;
@property NSString* dob;

+(SocialState*)getFacebookInstance;
-(void)reset;
-(void)updateFacebook;
-(void)update;
@end
