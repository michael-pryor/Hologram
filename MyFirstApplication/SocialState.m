//
//  SocialState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import "SocialState.h"
#import <FBSDKCoreKit/FBSDKCoreKit.h>

const NSString* selectedGenderPreferenceKey = @"selectedGenderPreference";

SocialState *instance;
typedef void (^Block)(id);

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
            [self loadInterestedInFromSegmentIndex:selectedGenderPreference];
        } else {
            NSLog(@"No previous gender preference selection found in storage, defaulting to BOTH");
            _interestedInI = BOTH;
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
    if (instance == nil) {
        instance = [[SocialState alloc] init];
    }

    return instance;
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
    } else {
        NSLog(@"Failed to load social details");
        [self reset];
    }
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
    FBSDKProfile *profile = [FBSDKProfile currentProfile];
    if (profile == nil) {
        [self reset];
        NSLog(@"Facebook state not ready yet, please request details from user");
        return;
    }

    [self loadStateFromFirstName:[profile firstName] middleName:[profile middleName] lastName:[profile lastName] facebookUrl:[profile linkURL] facebookId:[profile userID]];
}

- (uint)_parseGender:(NSString *)gender {
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

- (void)loadInterestedInFromSegmentIndex:(int)segmentIndex {
    if (segmentIndex == 0) {
        [self setInterestedIn:@"male"];
    } else if (segmentIndex == 1) {
        [self setInterestedIn:@"female"];
    } else if (segmentIndex == 2) {
        [self setInterestedIn:nil];
    }
}

- (uint)_getAgeFromDob:(NSString *)dob {
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

- (void)updateGraphFacebookInformation {
    if (![FBSDKAccessToken currentAccessToken]) {
        NSLog(@"Core Facebook information not loaded!");
        return;
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
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, secondsDelay * NSEC_PER_SEC), dispatch_get_main_queue(), ^ {
                    blockParam(blockParam);
                });
                return;
            }

            _dob = [result objectForKey:@"birthday"];
            if (_dob == nil) {
                NSLog(@"Failed to retrieve date of birth from Facebook API, defaulting to 0 - server will handle this");
                _age = 0;
            } else {
                _age = [self _getAgeFromDob:_dob];
            }

            _gender = [result objectForKey:@"gender"];
            if (_gender == nil) {
                NSLog(@"Failed to retrieve gender from Facebook API, defaulting to nil which will equate to BOTH - server will handle this");
            }
            _genderI = [self _parseGender:_gender];

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
}

- (void)update {
    [self updateCoreFacebookInformation];
    [self updateGraphFacebookInformation];
}

- (void)setInterestedIn:(NSString *)interestedIn {
    _interestedInI = [self _parseGender:interestedIn];
}

@end
