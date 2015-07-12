
//
//  SocialState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import "SocialState.h"
#import <FBSDKLoginKit/FBSDKLoginKit.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>

SocialState* instance;

@implementation SocialState

-(void)loadStateFromFirstName:(NSString*)firstName middleName:(NSString*)middleName lastName:(NSString*)lastName facebookUrl:(NSURL*)facebookUrl facebookId:(NSString*)facebookId {
    _firstName = firstName;
    _middleName = middleName;
    _lastName = lastName;
    _facebookUrl = facebookUrl;
    _facebookId = facebookId;
    
    NSString* seperator = @" ";
    NSMutableString* aux = [[NSMutableString alloc] init];
    Boolean setShortName = false;
    if(_firstName != nil) {
        [aux appendString:_firstName];
        [aux appendString:seperator];
        _humanShortName = _firstName;
        setShortName = true;
        
    }
    
    if(_middleName != nil) {
        [aux appendString:_middleName];
        [aux appendString:seperator];
    }
    
    if(_lastName != nil) {
        [aux appendString:_lastName];
        [aux appendString:seperator];
        
        if(!setShortName) {
            _humanShortName = _lastName;
            setShortName = true;
        }
    }
    
    if(!setShortName) {
        if(_middleName != nil) {
            _humanShortName = _middleName;
            setShortName = true;
        } else {
            _humanShortName = @"";
        }
    } else {
        // Delete the last character.
        // I know.. dat syntax...
        [aux deleteCharactersInRange:NSMakeRange([aux length]-1, 1)];
    }
    
    _humanFullName = aux;
    _isDataLoaded = setShortName;
    
    if(_isDataLoaded) {
        NSLog(@"Loaded social details: Full name = [%@], Short name: [%@], Facebook URL: [%@], Facebook ID: [%@]", _humanFullName, _humanShortName, _facebookUrl, _facebookId);
    } else {
        NSLog(@"Failed to load social details");
        [self reset];
    }
}

-(void)reset {
    _humanFullName = nil;
    _humanShortName = nil;
    _facebookId = nil;
    _facebookUrl = nil;
    _firstName = nil;
    _lastName = nil;
    _middleName = nil;
    _isDataLoaded = false;
}

- (void)loadStateFromFacebook {
    FBSDKProfile* profile = [FBSDKProfile currentProfile];
    if(profile == nil) {
        [self reset];
        NSLog(@"Facebook state not ready yet, please request details from user");
        return;
    }
    
    [self loadStateFromFirstName:[profile firstName] middleName:[profile middleName] lastName:[profile lastName] facebookUrl:[profile linkURL] facebookId:[profile userID]];
    
    [self _retrieveGraphInformation];
}

- (void)_retrieveGraphInformation {
    if ([FBSDKAccessToken currentAccessToken]) {
        [[[FBSDKGraphRequest alloc] initWithGraphPath:@"me" parameters:nil]
         startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
             if (!error) {
                // NSLog(@"Retrieved results from Facebook graph API: [%@]", result);
                _dob = [result objectForKey:@"birthday"];
                _gender = [result objectForKey:@"gender"];
                 
                 NSLog(@"Loaded DOB: [%@] and gender: [%@] from Facebook graph API", _dob, _gender);
             }
         }];
    }
}

+(SocialState*)getFacebookInstance {
    if(instance == nil) {
        [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
        instance = [[SocialState alloc] init];
    }
    return instance;
}

- (void)updateFacebook {
    [self loadStateFromFacebook];
}

- (void)update {
    [self updateFacebook];
}

@end
