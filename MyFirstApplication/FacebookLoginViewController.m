//
//  FacebookLoginViewController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 06/07/2015.
//
//

#import "FacebookLoginViewController.h"
#import "ConnectionViewController.h"

@implementation FacebookLoginViewController {
    Boolean _appeared;
    Boolean _autoSwitch;
    Boolean _initialized;
}
- (void)initialize {
    if(!_initialized) {
        _isDataLoaded = false;
        _appeared = false;
        _autoSwitch = true;
        _initialized = true;
    }
}

- (id)init {
    self = [super init];
    if(self) {
        _initialized = false;
        [self initialize];
    }
    return self;
}

- (void)signalBackwards {
    [_buttonFinished setHidden:false];
    _autoSwitch = false;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}
- (IBAction)onFinishedButtonClick:(id)sender {
    [self _switchToChatView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initialize];
    
    if(_autoSwitch) {
        [_buttonFinished setHidden:true];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileUpdated:) name:FBSDKProfileDidChangeNotification object:nil];
    [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];

    self.loginButton.readPermissions = @[@"public_profile", @"email", @"user_friends", @"user_birthday"];

    if ([FBSDKAccessToken currentAccessToken]) {
        NSLog(@"User is already logged in");
        [self _onLogin];
    } else {
        [self _updateDisplay];
    }

}

- (void)viewDidAppear:(BOOL)animated {
    _appeared = true;
    
    if(_isDataLoaded && _autoSwitch) {
        [self _switchToChatView];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    _appeared = false;
}

- (void)_updateDisplay {
    if(_isDataLoaded) {
        [_displayName setText:_humanFullName];
        [_displayPicture setProfileID:_facebookId];
    } else {
        [_displayName setText:@"Who are you?"];
        [_displayPicture setProfileID:nil];
    }
}

- (void)_switchToChatView {
    if(_appeared) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:nil];
        ConnectionViewController* viewController = (ConnectionViewController*)[storyboard instantiateViewControllerWithIdentifier:@"ConnectionView"];
        [self presentViewController:viewController animated:YES completion:nil];
    }
}

- (void)_onLogin {
    FBSDKProfile* profile = [FBSDKProfile currentProfile];
    _firstName = [profile firstName];
    _middleName = [profile middleName];
    _lastName = [profile lastName];
    _facebookUrl = [profile linkURL];
    _facebookId = [profile userID];
    
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
        NSLog(@"Logged in with user: [%@ (%@)] with facebook URL: [%@]", _humanFullName, _humanShortName, _facebookUrl);
    } else {
        NSLog(@"No profile information found; may be due to logout");
    }
    
    [self _updateDisplay];
    
    if(_isDataLoaded && _autoSwitch) {
        [self _switchToChatView];
    }
}

- (void)onProfileUpdated:(NSNotification*)notification {
    [self _onLogin];
}

- (void)loginButton:(FBSDKLoginButton*)loginButton didCompleteWithResult:(FBSDKLoginManagerLoginResult*)result error:(NSError*)error {
    if ([result isCancelled]) {
        NSLog(@"User cancelled login attempt");
    } else {
        NSLog(@"Logged in successfully, retrieving credentials...");
    }
}

- (void)loginButtonDidLogOut:(FBSDKLoginButton*)loginButton {
    NSLog(@"Logged out successfully");
}
@end
