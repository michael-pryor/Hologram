//
//  SocialState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 12/07/2015.
//
//

#import "SocialState.h"
#import "Timer.h"
#import "Analytics.h"
#import "KeychainItemWrapper.h"
#import "GenderParsing.h"
#import "DobParsing.h"
#import "NameParsing.h"
#import "ImageParsing.h"
#import <FBSDKCoreKit/FBSDKCoreKit.h>

NSString *selectedGenderPreferenceKey = @"selectedGenderPreference";
NSString *ownerGenderKey = @"ownerGender";
NSString *humanFullNameKey = @"humanFullName";
NSString *humanShortNameKey = @"humanShortName";
NSString *dobKey = @"dob";
NSString *profilePictureKey = @"profilePicture";
NSString *profilePictureOrientationKey = @"profilePictureOrientation";
NSString *callingCardTextKey = @"callingCardText";

NSString *hasAcceptedEulaKey = @"hasAcceptedEula";

NSString *selectedHotNotificationDaysKey = @"selectedHotNotificationDays";
NSString *isHotNotificationEnabledKey = @"isHotNotificationEnabled";

NSString *isLoadingFacebookDataKey = @"isLoadingFacebookData";

static SocialState *instance = nil;

typedef void (^Block)(id);


@implementation SocialState {
    id <SocialStateDataLoadNotification> _notifier;

    NSURL *_facebookProfilePictureUrl;

    bool _isGraphDataLoaded;
}

- (id)init {
    self = [super init];
    if (self) {
        [self reset];

        // Initialize here instead of in reset because this value doesn't come from Facebook.
        // It comes form a GUI item (direct from user).
        if ([[NSUserDefaults standardUserDefaults] objectForKey:selectedGenderPreferenceKey] != nil) {
            const int selectedGenderPreference = (int) [[NSUserDefaults standardUserDefaults] integerForKey:selectedGenderPreferenceKey];
            NSLog(@"Loaded previous gender preference selection from storage: %d", selectedGenderPreference);
            [self persistInterestedInWithSegmentIndex:selectedGenderPreference saving:false];
        } else {
            NSLog(@"No previous gender preference selection found in storage, defaulting to BOTH");
            [self persistInterestedInBoth];
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:ownerGenderKey] != nil) {
            const int ownerGender = (int) [[NSUserDefaults standardUserDefaults] integerForKey:ownerGenderKey];
            NSLog(@"Loaded previous owner gender selection from storage: %d", ownerGender);
            [self persistOwnerGenderWithSegmentIndex:ownerGender saving:false];
        } else {
            NSLog(@"No previous owner gender selection found in storage");
        }

        NSString *humanFullName;
        NSString *humanShortName;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:humanFullNameKey] != nil) {
            humanFullName = [[NSUserDefaults standardUserDefaults] stringForKey:humanFullNameKey];
            [self persistHumanFullName:humanFullName saving:false];
            NSLog(@"Loaded previous human name from storage: %@", humanFullName);
        } else {
            NSLog(@"No previous human full name found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:humanShortNameKey] != nil) {
            humanShortName = [[NSUserDefaults standardUserDefaults] stringForKey:humanShortNameKey];
            [self persistHumanShortName:humanShortName saving:false];
            NSLog(@"Loaded previous human short name from storage: %@", humanShortName);
        } else {
            NSLog(@"No previous human short name found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:dobKey] != nil) {
            NSString *dob = [[NSUserDefaults standardUserDefaults] stringForKey:dobKey];
            [self persistDateOfBirthObject:[DobParsing getDateObjectFromTextBoxString:dob] saving:false];
            NSLog(@"Loaded dob from storage: %@, age: %d", dob, _age);
        } else {
            NSLog(@"No date of birth found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:profilePictureKey] != nil) {

            NSData *profilePictureData = [[NSUserDefaults standardUserDefaults] objectForKey:profilePictureKey];

            uint profilePictureOrientationInteger = (uint) [[NSUserDefaults standardUserDefaults] integerForKey:profilePictureOrientationKey];
            UIImageOrientation profilePictureOrientation = [ImageParsing parseIntegerToOrientation:profilePictureOrientationInteger];
            UIImage *profilePictureImage = [ImageParsing convertDataToImage:profilePictureData orientation:profilePictureOrientation];

            [self persistProfilePictureImage:profilePictureImage prepareImage:false saving:false];
            NSLog(@"Loaded profile picture from storage, bytes: %lu", (unsigned long) [profilePictureData length]);
        } else {
            NSLog(@"No profile picture found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:callingCardTextKey] != nil) {
            NSString *callingCardText = [[NSUserDefaults standardUserDefaults] stringForKey:callingCardTextKey];
            [self persistCallingCardText:callingCardText saving:false];
            NSLog(@"Loaded previous calling card text: %@", callingCardText);
        } else {
            NSLog(@"No previous calling card text found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:hasAcceptedEulaKey] != nil) {
            const bool hasAcceptedEula = [[NSUserDefaults standardUserDefaults] boolForKey:hasAcceptedEulaKey];
            NSLog(@"Loaded EULA accepted boolean from storage: %d", hasAcceptedEula);
            [self persistHasAcceptedEula:hasAcceptedEula saving:false];
        } else {
            NSLog(@"No previous owner gender selection found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:isHotNotificationEnabledKey] != nil) {
            const bool isHotEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:isHotNotificationEnabledKey];
            NSLog(@"Loaded hot notification enabled boolean from storage: %d", isHotEnabled);
            [self persistIsHotNotificationEnabled:isHotEnabled saving:false];
        } else {
            NSLog(@"No previous hot notification enabled found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:selectedHotNotificationDaysKey] != nil) {
            NSArray *hotNotificationDays = [[NSUserDefaults standardUserDefaults] arrayForKey:selectedHotNotificationDaysKey];
            [self persistHotNotificationDays:hotNotificationDays saving:false];
            NSLog(@"Loaded hot notification days from storage: %@", hotNotificationDays);
        } else {
            NSLog(@"No date of birth found in storage");
        }

        if ([[NSUserDefaults standardUserDefaults] objectForKey:isLoadingFacebookDataKey] != nil) {
            const bool isLoadingFacebookData = [[NSUserDefaults standardUserDefaults] boolForKey:isLoadingFacebookDataKey];
            NSLog(@"Loaded is loading facebook data boolean from storage: %d", isLoadingFacebookData);
            [self persistIsLoadingFacebookData:isLoadingFacebookData saving:false];
        } else {
            NSLog(@"No previous is loading facebook data boolean found in storage");
        }
    }
    return self;
}

- (void)persistIsLoadingFacebookData:(bool)isLoadingFacebookData saving:(bool)doSave {
    _isLoadingFacebookData = isLoadingFacebookData;

    if (doSave) {
        NSLog(@"Persisting is loading facebook data boolean: %d", _isLoadingFacebookData);
        [[NSUserDefaults standardUserDefaults] setBool:_isLoadingFacebookData forKey:isLoadingFacebookDataKey];
    }
}

- (void)persistIsLoadingFacebookData:(bool)isLoadingFacebookData {
    [self persistIsLoadingFacebookData:isLoadingFacebookData saving:true];
}

- (void)persistHotNotificationDays:(NSArray*)hotNotificationDays saving:(bool)doSave {
    _hotNotificationDays = hotNotificationDays;

    if (doSave) {
        NSLog(@"Persisting hot notification days: %@", _hotNotificationDays);
        [[NSUserDefaults standardUserDefaults] setObject:_hotNotificationDays forKey:selectedHotNotificationDaysKey];
    }
}

- (void)persistHotNotificationDays:(NSArray*)hotNotificationDays {
    [self persistHotNotificationDays:hotNotificationDays saving:true];
}

- (void)persistIsHotNotificationEnabled:(bool)isHotNotificationEnabled saving:(bool)doSave {
    _isHotNotificationEnabled = isHotNotificationEnabled;

    if (doSave) {
        NSLog(@"Persisting is hot enabled: %d", _isHotNotificationEnabled);
        [[NSUserDefaults standardUserDefaults] setBool:_isHotNotificationEnabled forKey:isHotNotificationEnabledKey];
    }
}

- (void)persistIsHotNotificationEnabled:(bool)isHotNotificationEnabled {
    [self persistIsHotNotificationEnabled:isHotNotificationEnabled saving:true];
}

- (void)persistHasAcceptedEula:(bool)hasAcceptedEula saving:(bool)doSave {
    _hasAcceptedEula = hasAcceptedEula;

    if (doSave) {
        NSLog(@"Persisting has accepted EULA: %d", _hasAcceptedEula);
        [[NSUserDefaults standardUserDefaults] setBool:_hasAcceptedEula forKey:hasAcceptedEulaKey];
    }
}

- (void)persistHasAcceptedEula {
    [self persistHasAcceptedEula:true saving:true];
}

- (void)persistProfilePictureImage:(UIImage *)image prepareImage:(bool)prepare saving:(bool)doSave {
    if (image != nil && prepare) {
        image = [ImageParsing prepareImage:image];
    }

    _profilePictureImage = image;
    _profilePictureData = [ImageParsing convertImageToData:image];
    _profilePictureOrientationInteger = [ImageParsing parseOrientationToInteger:[image imageOrientation]];
    _profilePictureOrientation = [ImageParsing parseIntegerToOrientation:_profilePictureOrientationInteger];

    if (doSave) {
        NSLog(@"Persisting profile picture image, bytes: %lu", (unsigned long) [_profilePictureData length]);
        [[NSUserDefaults standardUserDefaults] setObject:_profilePictureData forKey:profilePictureKey];
        [[NSUserDefaults standardUserDefaults] setInteger:_profilePictureOrientationInteger forKey:profilePictureOrientationKey];
    }
}

- (void)persistProfilePictureImage:(UIImage *)image {
    [self persistProfilePictureImage:image prepareImage:true saving:true];
}

- (void)registerNotifier:(id <SocialStateDataLoadNotification>)notifier {
    _notifier = notifier;
}

- (bool)isDataLoadedAndEulaAccepted {
    // If has not accepted EULA, needs to go back to FB login screen.
    return _hasAcceptedEula && [self isDataLoaded];
}

- (bool)isDataLoaded {
    return _profilePictureImage != nil && _humanShortName != nil && _humanFullName != nil && _genderSegmentIndex != UISegmentedControlNoSegment && _interestedInSegmentIndex != UISegmentedControlNoSegment && _age >= MINIMUM_AGE;
}

- (void)persistHumanFullName:(NSString *)humanFullName saving:(bool)doSave {
    _humanFullName = humanFullName;

    if (doSave) {
        [[NSUserDefaults standardUserDefaults] setObject:_humanFullName forKey:humanFullNameKey];
    }
}

- (void)persistHumanShortName:(NSString *)humanShortName saving:(bool)doSave {
    _humanShortName = humanShortName;

    if (doSave) {
        [[NSUserDefaults standardUserDefaults] setObject:_humanShortName forKey:humanShortNameKey];
    }
}

- (void)persistStateFromFirstName:(NSString *)firstName middleName:(NSString *)middleName lastName:(NSString *)lastName saving:(bool)doSave {
    NSMutableString *humanFullName = [[NSMutableString alloc] init];
    NSString *humanShortName = [NameParsing getShortNameAndBuildLongName:humanFullName firstName:firstName middleName:middleName lastName:lastName];
    [self persistHumanFullName:humanFullName saving:doSave];
    [self persistHumanShortName:humanShortName saving:doSave];
}

- (void)persistDateOfBirthObject:(NSDate *)dateOfBirth saving:(bool)doSave {
    _dobObject = dateOfBirth;
    _dobString = [DobParsing getTextBoxStringFromDateObject:_dobObject]; // in the correct format.
    _age = [DobParsing getAgeFromDateObject:_dobObject];

    if (doSave) {
        [[NSUserDefaults standardUserDefaults] setObject:_dobString forKey:dobKey];
    }
}

- (void)persistHumanFullName:(NSString *)humanFullName humanShortName:(NSString *)humanShortName {
    [self persistHumanFullName:humanFullName saving:true];
    [self persistHumanShortName:humanShortName saving:true];
}

- (void)persistDateOfBirthObject:(NSDate *)dateOfBirth {
    [self persistDateOfBirthObject:dateOfBirth saving:true];
}

- (void)reset {
    _humanFullName = nil;
    _humanShortName = nil;
    _genderSegmentIndex = UISegmentedControlNoSegment;
    _genderEnum = 0;
    _genderString = nil;
    _age = 0;
    _isGraphDataLoaded = false;
    _facebookProfilePictureUrl = nil;
    _profilePictureImage = nil;
    _profilePictureData = nil;
    _profilePictureOrientation = UIImageOrientationUp;
    _profilePictureOrientationInteger = [ImageParsing parseOrientationToInteger:_profilePictureOrientation];
}

- (bool)updateFromFacebookCore {
    // It is possible for the two conditions to be disjoint i.e. profile to be non nil while access token is nil.
    // That is why we check both, because graph API requires token.
    FBSDKProfile *profile = nil;
    if ([FBSDKAccessToken currentAccessToken]) {
        profile = [FBSDKProfile currentProfile];
    }

    if (profile == nil) {
        NSLog(@"Facebook state not ready yet, please request details from user");
        return false;
    } else {
        CGSize size;
        size.width = [ImageParsing getDefaultWidthAndHeight];
        size.height = size.width;
        _facebookProfilePictureUrl = [profile imageURLForPictureMode:FBSDKProfilePictureModeSquare size:size];
    }

    [self persistStateFromFirstName:[profile firstName] middleName:[profile middleName] lastName:[profile lastName] saving:true];
    return true;
}


- (void)persistInterestedInBoth {
    [self persistInterestedInWithSegmentIndex:INTERESTED_IN_BOTH_SEGMENT_ID];
}

- (void)persistInterestedInWithSegmentIndex:(int)segmentIndex {
    [self persistInterestedInWithSegmentIndex:segmentIndex saving:true];
}

- (void)persistInterestedInWithSegmentIndex:(int)segmentIndex saving:(bool)doSave {
    _interestedIn = [GenderParsing parseGenderSegmentIndex:segmentIndex];
    _interestedInSegmentIndex = segmentIndex;

    if (doSave) {
        NSLog(@"Saving interested in segment index of %d", segmentIndex);
        [[NSUserDefaults standardUserDefaults] setInteger:segmentIndex forKey:selectedGenderPreferenceKey];
    }
}

- (void)persistOwnerGenderWithSegmentIndex:(int)segmentIndex {
    [self persistOwnerGenderWithSegmentIndex:segmentIndex saving:true];
}

- (void)setOwnerGenderWithString:(NSString *)genderString saving:(bool)doSave {
    _genderString = genderString;
    _genderEnum = [GenderParsing parseGenderString:genderString];
    _genderSegmentIndex = [GenderParsing parseGenderStringToSegmentIndex:genderString];

    [Analytics updateGender:genderString];

    if (doSave) {
        NSLog(@"Saving owner gender segment index of %d", _genderSegmentIndex);
        [[NSUserDefaults standardUserDefaults] setInteger:_genderSegmentIndex forKey:ownerGenderKey];
    }
}

- (void)persistOwnerGenderWithSegmentIndex:(int)segmentIndex saving:(bool)doSave {
    NSString *gender = [GenderParsing parseGenderSegmentIndexToString:segmentIndex];
    [self setOwnerGenderWithString:gender saving:doSave];
}

- (void)persistCallingCardText:(NSString *)text saving:(bool)doSave {
    _callingCardText = text;

    if (doSave) {
        NSLog(@"Saving calling card text: %@", _callingCardText);
        [[NSUserDefaults standardUserDefaults] setObject:_callingCardText forKey:callingCardTextKey];
    }
}

- (void)persistCallingCardText:(NSString *)text {
    [self persistCallingCardText:text saving:true];
}

- (bool)updateFromFacebookGraph {
    if (![FBSDKAccessToken currentAccessToken]) {
        NSLog(@"Core Facebook information not loaded!");
        return false;
    }

    NSDictionary *parameters = @{@"fields" : @"id,name,birthday,gender"};
    FBSDKGraphRequest *fbGraphRequest = [[FBSDKGraphRequest alloc] initWithGraphPath:@"me" parameters:parameters];

    __block Timer *fbGraphRequestTimer = [[Timer alloc] init];

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

            // We may get updates, even if user hasn't recently logged in, i.e. we can get multiple (some may be hours or days later).
            if (![self isLoadingFacebookData]) {
                NSLog(@"Facebook profile graph update received, IGNORING!!");
            }

            // Prevent further updates. User has to logout and in again first.
            [self persistIsLoadingFacebookData:false];

            NSString *dob = [result objectForKey:@"birthday"];
            if (dob == nil) {
                NSLog(@"Failed to retrieve date of birth from Facebook API");
            } else {
                [self persistDateOfBirthObject:[DobParsing getDateObjectFromFacebookString:dob] saving:true];
            }

            NSString *gender = [result objectForKey:@"gender"];
            if (gender == nil) {
                NSLog(@"Failed to retrieve gender from Facebook graph API");
            } else {
                [self setOwnerGenderWithString:gender saving:true];
            }

            NSLog(@"Loaded DOB: [%@], gender: [%@] from Facebook graph API", dob, _genderString);
            _isGraphDataLoaded = true;
            [[Analytics getInstance] pushTimer:fbGraphRequestTimer withCategory:@"setup" name:@"facebook_graph"];

            if (_facebookProfilePictureUrl != nil) {
                // This is synchronous.
                NSData *imageData = [[NSData alloc] initWithContentsOfURL:_facebookProfilePictureUrl];
                UIImage *image = [UIImage imageWithData:imageData];
                [self persistProfilePictureImage:image];
            }

            if (_notifier != nil) {
                [_notifier onSocialDataLoaded:self];
            }
        }];
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        block(block);
    });

    return true;
}

+ (SocialState *)getSocialInstance {
    @synchronized (self) {
        if (instance == nil) {
            instance = [[SocialState alloc] init];
        }

        return instance;
    }
}

@end
