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
static NSString *gpsSaveKey = @"previousGpsLocation";

@implementation GpsState {
    CLLocationManager *_locationManager;
    id <GpsStateDataLoadNotification> _notifier;
    Signal *_loaded;

    Timer *_loadingTimer;

    NSTimeInterval _gpsUpdateTimeout;

    Signal *_loadingInProgress;
}

- (id)initWithNotifier:(id <GpsStateDataLoadNotification>)notifier timeout:(NSTimeInterval)gpsUpdateTimeout {
    self = [super init];
    if (self) {
        _notifier = notifier;
        _loaded = [[Signal alloc] initWithFlag:false];
        _loadingInProgress = [[Signal alloc] initWithFlag:false];
        _loadingTimer = [[Timer alloc] init];
        _gpsUpdateTimeout = gpsUpdateTimeout;
    }
    return self;
}

- (bool)isLoaded {
    return [_loaded isSignaled];
}

- (void)update {
    // Create the location manager if this object does not
    // already have one.
    if (nil == _locationManager && [_loadingInProgress signalAll]) {
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

        __block GpsState *blockGpsState = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) _gpsUpdateTimeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (![blockGpsState->_loadingInProgress clear]) {
                return;
            }

            [blockGpsState onGpsResolutionTimeout];
        });
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

    [self onGpsResolutionSuccessLongitude:_longitude latitude:_latitude];
    if ([_loaded signalAll]) {
        [_loadingInProgress clear];
        [[Analytics getInstance] pushTimer:_loadingTimer withCategory:@"setup" name:@"gps" label:@"normal_lookup"];
        [self notifySuccess];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSArray *)locations {
    NSLog(@"Error retrieving GPS location");
    if (![_loaded isSignaled]) {
        NSLog(@"Total failure to retrieve GPS");
        if (_notifier != nil) {
            [_notifier onGpsDataLoadFailure:self withDescription:@"Failed to load GPS position"];
        }
    } else {
        NSLog(@"GPS location update failed but we have already loaded a location, so ignoring error; on next login old GPS location will be reused");
    }

}

- (void)onGpsResolutionSuccessLongitude:(float)lng latitude:(float)lat {
    NSLog(@"Updating GPS record [%.2f, %.2f]", lng, lat);
    [[NSUserDefaults standardUserDefaults] setObject:@[@(lng), @(lat)] forKey:gpsSaveKey];
}

- (void)onGpsResolutionTimeout {
    if (![_loaded signalAll]) {
        return;
    }

    NSArray *result = [[NSUserDefaults standardUserDefaults] arrayForKey:gpsSaveKey];
    if (result == nil) {
        // Lolz
        NSLog(@"Failed to load GPS location, defaulting to buckingham palace");
        result = @[@(-0.141847), @(51.501207)];
    }

    NSNumber *lngObj = result[0];
    NSNumber *latObj = result[1];
    _longitude = [lngObj floatValue];
    _latitude = [latObj floatValue];

    NSLog(@"Retrieved GPS record from storage [%.2f, %.2f]", _longitude, _latitude);

    [[Analytics getInstance] pushTimer:_loadingTimer withCategory:@"setup" name:@"gps" label:@"previous_lookup"];
    [self notifySuccess];
}
@end
