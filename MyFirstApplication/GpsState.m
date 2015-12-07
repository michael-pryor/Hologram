//
//  GpsState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 13/07/2015.
//
//

#import "GpsState.h"

GpsState *state;

@implementation GpsState {
    CLLocationManager *_locationManager;
    id <GpsStateDataLoadNotification> _notifier;
}

- (id)initWithNotifier:(id <GpsStateDataLoadNotification>)notifier {
    self = [super init];
    if (self) {
        _notifier = notifier;
        _loaded = false;
    }
    return self;
}

- (void)update {
    // Create the location manager if this object does not
    // already have one.
    if (nil == _locationManager) {
        _locationManager = [[CLLocationManager alloc] init];

        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;

        // Set a movement threshold for new events.
        _locationManager.distanceFilter = 500; // meters

        // Check for iOS 8. Without this guard the code will crash with "unknown selector" on iOS 7.
        if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
            [_locationManager requestWhenInUseAuthorization];
        }
        
        // Now we receive updates initially, and every time we change locaiton.
        [_locationManager startUpdatingLocation];
    } else {
        if (_loaded) {
            if (_notifier != nil) {
                [_notifier onGpsDataLoaded:self];
            }
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *location = [locations lastObject];

    double age = fabs([location.timestamp timeIntervalSinceNow]);
    double horizontalAccuracy = [location horizontalAccuracy];
    double verticalAccuracy = [location verticalAccuracy];
    double altitude = [location altitude];
    _latitude = [location coordinate].latitude;
    _longitude = [location coordinate].longitude;
    NSString *description = [location description];

    NSLog(@"Loaded GPS location (%.2f seconds old): %.2f,%.2f / %.2f with accuracy %.2f,%.2f - description: %@", age, _longitude, _latitude, altitude, horizontalAccuracy, verticalAccuracy, description);

    if (!_loaded) {
        _loaded = true;
        if (_notifier != nil) {
            [_notifier onGpsDataLoaded:self];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSArray *)locations {
    NSLog(@"Error retrieving GPS location");
    if (_notifier != nil) {
        if (!_loaded) {
            NSLog(@"Total failure to retrieve GPS");
            [_notifier onGpsDataLoadFailure:self withDescription:@"Failed to load GPS position"];
        } else {
            NSLog(@"Reusing old GPS location");
            // Use last retrieved location.
            //[_notifier onGpsDataLoaded:self];
        }
    }
}
@end
