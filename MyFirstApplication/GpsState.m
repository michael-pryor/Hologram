//
//  GpsState.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 13/07/2015.
//
//

#import "GpsState.h"

GpsState * state;

@implementation GpsState {
    CLLocationManager * _locationManager;
}
+(GpsState*)getInstance {
    if(state == nil) {
        state = [[GpsState alloc] init];
    }
    return state;
}
- (void)update {
    // Create the location manager if this object does not
    // already have one.
    if (nil == _locationManager) {
        _locationManager = [[CLLocationManager alloc] init];
    }
    
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;
    
    // Set a movement threshold for new events.
    _locationManager.distanceFilter = 500; // meters
    
    [_locationManager startUpdatingLocation];
}
- (void)locationManager:(CLLocationManager*)manager didUpdateLocations:(NSArray*)locations {
    CLLocation* location = [locations lastObject];
    
    double age = fabs([location.timestamp timeIntervalSinceNow]);
    double horizontalAccuracy = [location horizontalAccuracy];
    double verticalAccuracy = [location verticalAccuracy];
    double altitude = [location altitude];
    _latitude = [location coordinate].latitude;
    _longitude = [location coordinate].longitude;
    NSString* description = [location description];
    
    NSLog(@"Loaded GPS location (%.2f seconds old): %.2f,%.2f / %.2f with accuracy %.2f,%.2f - description: %@", age, _longitude, _latitude, altitude, horizontalAccuracy, verticalAccuracy, description);
    
    _loaded = true;
    
}

- (void)locationManager:(CLLocationManager*)manager didFailWithError:(NSArray*)locations {
    NSLog(@"Error retrieving GPS location");
}
@end
