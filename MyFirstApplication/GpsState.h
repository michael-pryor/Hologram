//
//  GpsState.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 13/07/2015.
//
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface GpsState : NSObject<CLLocationManagerDelegate>
+(GpsState*)getInstance;
- (void)update;

@property double longitude;
@property double latitude;
@property Boolean loaded;
@end
