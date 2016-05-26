//
//  GpsState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 13/07/2015.
//
//

#import "GpsState.h"
#import "Signal.h"
#import "Timer.h"
#import "Analytics.h"

GpsState *state;

@implementation GpsState {
    CLLocationManager *_locationManager;
    id <GpsStateDataLoadNotification> _notifier;
    Signal *_loaded;

    Timer *_loadingTimer;
}

- (id)initWithNotifier:(id <GpsStateDataLoadNotification>)notifier {
    self = [super init];
    if (self) {
        _notifier = notifier;
        _loaded = [[Signal alloc] initWithFlag:false];
        _loadingTimer = [[Timer alloc] init];
    }
    return self;
}

- (bool)isLoaded {
    return [_loaded isSignaled];
}

- (void)update {
    // Create the location manager if this object does not
    // already have one.
    if (nil == _locationManager) {
        _locationManager = [[CLLocationManager alloc] init];

        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;

        // Set a movement threshold for new events.
        _locationManager.distanceFilter = 1000; // meters

        // Check for iOS 8. Without this guard the code will crash with "unknown selector" on iOS 7.
        if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
            [_locationManager requestWhenInUseAuthorization];
        }

        // Now we receive updates initially, and every time we change location.
        [_loadingTimer reset];
        [_locationManager startUpdatingLocation];
    } else {
        if ([_loaded isSignaled]) {
            [self notifySuccess];
        }
    }
}

- (void)notifySuccess {
    if (_notifier != nil) {
        [_notifier onGpsDataLoaded:self];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *location = [locations lastObject];

    double age = fabs([location.timestamp timeIntervalSinceNow]);
    double horizontalAccuracy = [location horizontalAccuracy];
    double verticalAccuracy = [location verticalAccuracy];
    double altitude = [location altitude];
    _latitude = (float) [location coordinate].latitude;
    _longitude = (float) [location coordinate].longitude;
    NSString *description = [location description];

    NSLog(@"Loaded GPS location (%.2f seconds old): %.2f,%.2f / %.2f with accuracy %.2f,%.2f - description: %@", age, _longitude, _latitude, altitude, horizontalAccuracy, verticalAccuracy, description);

    if ([_loaded signalAll]) {
        [[Analytics getInstance] pushTimer:_loadingTimer toAnalyticsWithCategory:@"setup_duration" name:@"gps"];
        [self notifySuccess];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSArray *)locations {
    NSLog(@"Error retrieving GPS location");
    if (_notifier != nil) {
        if (![_loaded isSignaled]) {
            NSLog(@"Total failure to retrieve GPS");
            [_notifier onGpsDataLoadFailure:self withDescription:@"Failed to load GPS position"];
        } else {
            NSLog(@"GPS location update failed but we have already loaded a location, so ignoring error; on next login old GPS location will be reused");
        }
    }
}
@end
