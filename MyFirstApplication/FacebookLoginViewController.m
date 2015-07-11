//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import "FacebookLoginViewController.h"

@implementation FacebookLoginViewController
- (id)init {
    self = [super init];
    if(self) {

    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileUpdated:) name:FBSDKProfileDidChangeNotification object:nil];
    [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];

    self.loginButton.readPermissions = @[@"public_profile", @"email", @"user_friends", @"user_birthday"];

    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
        [self _onLogin];
    }

}

- (void)_onLogin {
    FBSDKProfile* profile = [FBSDKProfile currentProfile];
    _firstName = [profile firstName];
    _middleName = [profile middleName];
    _lastName = [profile lastName];
    _facebookUrl = [profile linkURL];
    
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
    
    if(setShortName) {
        NSLog(@"Logged in with user: [%@ (%@)] with facebook URL: [%@]", _humanFullName, _humanShortName, _facebookUrl);
    } else {
        NSLog(@"No profile information found");
    }
}

- (void)onProfileUpdated:(NSNotification*)notification {
    [self _onLogin];
}

- (void)loginButton:(FBSDKLoginButton*)loginButton didCompleteWithResult:(FBSDKLoginManagerLoginResult*)result error:(NSError*)error {
    if ([result isCancelled]) {
        NSLog(@"Cancelled");
    } else {
        NSLog(@"Logged in, retrieving credentials");
    }
}

- (void)loginButtonDidLogOut:(FBSDKLoginButton*)loginButton {
    NSLog(@"Logged out");
}
@end
