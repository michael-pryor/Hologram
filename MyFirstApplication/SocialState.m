//
//  SocialState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import "SocialState.h"
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import <Google/Analytics.h>

const NSString* selectedGenderPreferenceKey = @"selectedGenderPreference";

SocialState *instance;
typedef void (^Block)(id);

#define INTERESTED_IN_BOTH_SEGMENT_ID 2

@implementation SocialState {
    id <SocialStateDataLoadNotification> _notifier;
}

- (id)init {
    self = [super init];
    if (self) {
        // Initialize here instead of in reset because this value doesn't come from Facebook.
        // It comes form a GUI item (direct from user).
        if([[NSUserDefaults standardUserDefaults] objectForKey:selectedGenderPreferenceKey] != nil) {
            const int selectedGenderPreference = [[NSUserDefaults standardUserDefaults] integerForKey:selectedGenderPreferenceKey];
            NSLog(@"Loaded previous gender preference selection from storage: %d", selectedGenderPreference);
            [self setInterestedInWithSegmentIndex:selectedGenderPreference saving:false];
        } else {
            NSLog(@"No previous gender preference selection found in storage, defaulting to BOTH");
            [self setInterestedInBoth];
        }
    }
    return self;
}

- (void)registerNotifier:(id <SocialStateDataLoadNotification>)notifier {
    _notifier = notifier;
}

- (void)unregisterNotifier {
    _notifier = nil;
}

- (Boolean)isDataLoaded {
    return _isBasicDataLoaded && _isGraphDataLoaded;
}

+ (SocialState *)getFacebookInstance {
    @synchronized (self) {
        if (instance == nil) {
            instance = [[SocialState alloc] init];
        }

        return instance;
    }
}

- (void)loadStateFromFirstName:(NSString *)firstName middleName:(NSString *)middleName lastName:(NSString *)lastName facebookUrl:(NSURL *)facebookUrl facebookId:(NSString *)facebookId {
    _firstName = firstName;
    _middleName = middleName;
    _lastName = lastName;
    _facebookUrl = facebookUrl;
    _facebookId = facebookId;

    NSString *seperator = @" ";
    NSMutableString *aux = [[NSMutableString alloc] init];
    Boolean setShortName = false;
    if (_firstName != nil) {
        [aux appendString:_firstName];
        [aux appendString:seperator];
        _humanShortName = _firstName;
        setShortName = true;

    }

    if (_middleName != nil) {
        [aux appendString:_middleName];
        [aux appendString:seperator];
    }

    if (_lastName != nil) {
        [aux appendString:_lastName];
        [aux appendString:seperator];

        if (!setShortName) {
            _humanShortName = _lastName;
            setShortName = true;
        }
    }

    if (!setShortName) {
        if (_middleName != nil) {
            _humanShortName = _middleName;
            setShortName = true;
        } else {
            _humanShortName = @"?";
        }
    } else {
        // Delete the last character.
        // I know.. dat syntax...
        [aux deleteCharactersInRange:NSMakeRange([aux length] - 1, 1)];
    }

    _humanFullName = aux;
    _isBasicDataLoaded = setShortName;

    if (_isBasicDataLoaded) {
        NSLog(@"Loaded social details: Full name = [%@], Short name: [%@], Facebook URL: [%@], Facebook ID: [%@]", _humanFullName, _humanShortName, _facebookUrl, _facebookId);
        [self _updateAnalyticsUser];
    } else {
        NSLog(@"Failed to load social details");
        [self reset];
    }
}

- (NSString*)_retrieveUserUUID: (NSString*)facebookID {
    // Unique ID used to identify this user going forwards.
    NSString *UUID = [[NSUUID UUID] UUIDString];
    NSString *masterKey = @"trackedFacebookUUIDs";

    NSDictionary *result = [[NSUserDefaults standardUserDefaults] dictionaryForKey:masterKey];
    if (result == nil) {
        // This is the first item, so add it and we're done.
        [[NSUserDefaults standardUserDefaults] setObject:@{facebookID : UUID} forKey:masterKey];
        NSLog(@"Associated first facebook ID [%@] with UUID [%@]", facebookID, UUID);
    } else {
        NSString * existingId = result[facebookID];
        if (existingId == nil) {
            NSMutableDictionary *mutableDict = [result mutableCopy];
            mutableDict[facebookID] = UUID;
            [[NSUserDefaults standardUserDefaults] setObject:mutableDict forKey:masterKey];
            NSLog(@"Associated another facebook ID [%@] with UUID [%@]", facebookID, UUID);
        } else {
            UUID = existingId;
            NSLog(@"Retrieved existing facebook ID [%@] with UUID [%@]", facebookID, UUID);
        }
    }

    return UUID;
}

- (void)_updateAnalyticsUser {
    NSString* UUID = [self _retrieveUserUUID:_facebookId];
    NSLog(@"Prepared Google analytics tracker with UUID: %@", UUID);

    id <GAITracker> tracker = [[GAI sharedInstance] defaultTracker];

    // User tracking must be enabled in Google analytics.
    [tracker set:kGAIUserId value:UUID];
}

- (void)reset {
    _humanFullName = nil;
    _humanShortName = nil;
    _facebookId = nil;
    _facebookUrl = nil;
    _firstName = nil;
    _lastName = nil;
    _middleName = nil;
    _genderI = 0;
    _gender = nil;
    _age = 0;
    _isBasicDataLoaded = false;
    _isGraphDataLoaded = false;
}

- (void)updateCoreFacebookInformation {
    // It is possible for the two conditions to be disjoint i.e. profile to be non nil while access token is nil.
    // That is why we check both, because graph API requires token.
    FBSDKProfile *profile = nil;
    if ([FBSDKAccessToken currentAccessToken]) {
       profile = [FBSDKProfile currentProfile];
    }

    if (profile == nil) {
        [self reset];
        NSLog(@"Facebook state not ready yet, please request details from user");
        return;
    }

    [self loadStateFromFirstName:[profile firstName] middleName:[profile middleName] lastName:[profile lastName] facebookUrl:[profile linkURL] facebookId:[profile userID]];
}

- (uint)parseGenderFromFacebookApi:(NSString *)gender {
    if (gender == nil) {
        return BOTH;
    } else if ([@"male" isEqualToString:gender]) {
        return MALE;
    } else if ([@"female" isEqualToString:gender]) {
        return FEMALE;
    } else {
        // Facebook API tells us that this can't happen.
        NSLog(@"Unknown gender: %@", gender);
        return BOTH;
    }
}

- (void)setInterestedInWithSegmentIndex:(int)segmentIndex saving:(bool)doSave {
    if (segmentIndex == 0) {
        [self setInterestedIn:@"male"];
    } else if (segmentIndex == 1) {
        [self setInterestedIn:@"female"];
    } else if (segmentIndex == INTERESTED_IN_BOTH_SEGMENT_ID) {
        [self setInterestedIn:nil];
    } else {
        [NSException raise:@"Invalid interested in segment index" format:@"segment index %d is invalid", segmentIndex];
    }

    _interestedInSegmentIndex = segmentIndex;

    if (doSave) {
        NSLog(@"Saving interested in segment index of %d", segmentIndex);
        [[NSUserDefaults standardUserDefaults] setInteger:segmentIndex forKey:selectedGenderPreferenceKey];
    }
}

- (void)setInterestedInBoth {
    [self setInterestedInWithSegmentIndex:INTERESTED_IN_BOTH_SEGMENT_ID];
}

- (void)setInterestedInWithSegmentIndex:(int)segmentIndex {
    [self setInterestedInWithSegmentIndex:segmentIndex saving:true];
}

- (uint)getAgeFromDateOfBirth:(NSString *)dob {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

    if ([dob length] == 4) {
        [dateFormatter setDateFormat:@"yyyy"];
    } else if ([dob length] == 5) {
        [dateFormatter setDateFormat:@"MM/dd"];
    } else {
        [dateFormatter setDateFormat:@"MM/dd/yyyy"];
    }

    NSDate *date = [dateFormatter dateFromString:dob];


    NSDate *now = [NSDate date];
    NSDateComponents *ageComponents = [[NSCalendar currentCalendar]
            components:NSCalendarUnitYear
              fromDate:date
                toDate:now
               options:0];
    NSInteger age = [ageComponents year];
    return (uint) age;
}

- (bool)updateGraphFacebookInformation {
    if (![FBSDKAccessToken currentAccessToken]) {
        NSLog(@"Core Facebook information not loaded!");
        return false;
    }

    NSDictionary *parameters = @{@"fields" : @"id,name,birthday,gender"};
    FBSDKGraphRequest *fbGraphRequest = [[FBSDKGraphRequest alloc] initWithGraphPath:@"me" parameters:parameters];

    // Repeatedly runs block (polling graph API) until successful.
    // This is useful if there are network issues temporarily, ensures we don't get stuck loading Facebook data.
    Block block = ^(Block blockParam) {
        NSLog(@"Retrieving Facebook graph API information");
        [fbGraphRequest startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
            if (error) {
                int secondsDelay = 1;
                NSLog(@"Error accessing graph API: %@, retrying in %d second", error, secondsDelay);

                if (_isGraphDataLoaded) {
                    NSLog(@"Not scheduling retry attempt for loading Facebook data, had previously succeeded");
                    return;
                }

                // Retry attempt.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, secondsDelay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    blockParam(blockParam);
                });
                return;
            }

            id <GAITracker> tracker = [[GAI sharedInstance] defaultTracker];

            _dob = [result objectForKey:@"birthday"];
            if (_dob == nil) {
                NSLog(@"Failed to retrieve date of birth from Facebook API, defaulting to 0 - server will handle this");
                _age = 0;
            } else {
                _age = [self getAgeFromDateOfBirth:_dob];

                // The dimension index must be setup in Google analytics.
                [tracker set:[GAIFields customDimensionForIndex:1] value:[[NSString alloc] initWithFormat:@"%d", _age]];
            }

            _gender = [result objectForKey:@"gender"];
            if (_gender == nil) {
                NSLog(@"Failed to retrieve gender from Facebook API, defaulting to nil which will equate to BOTH - server will handle this");
            } else {
                // The dimension index must be setup in Google analytics.
                [tracker set:[GAIFields customDimensionForIndex:2] value:_gender];
            }
            _genderI = [self parseGenderFromFacebookApi:_gender];

            NSLog(@"Loaded DOB: [%@], gender: [%@] from Facebook graph API", _dob, _gender);
            _isGraphDataLoaded = true;
            if (_notifier != nil) {
                [_notifier onSocialDataLoaded:self];
            }
        }];
    };

    dispatch_async(dispatch_get_main_queue(), ^ {
        block(block);
    });

    return true;
}

- (void)update {
    [self updateCoreFacebookInformation];
    [self updateGraphFacebookInformation];
}

- (void)setInterestedIn:(NSString *)interestedIn {
    _interestedIn = [self parseGenderFromFacebookApi:interestedIn];
}

@end
