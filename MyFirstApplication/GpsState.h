//
//  GpsState.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 13/07/2015.
//
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class GpsState;

@protocol GpsStateDataLoadNotification <NSObject>
- (void)onGpsDataLoaded:(GpsState *)state;

- (void)onGpsDataLoadFailure:(GpsState *)state withDescription:(NSString *)description;
@end

@interface GpsState : NSObject <CLLocationManagerDelegate>
- (void)update;

@property float longitude;
@property float latitude;

- (bool)isLoaded;

- (id)initWithNotifier:(id <GpsStateDataLoadNotification>)notifier timeout:(NSTimeInterval)gpsUpdateTimeout;
@end
