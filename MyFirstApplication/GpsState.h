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

@protocol GpsStateDataLoadNotification<NSObject>
-(void)onDataLoaded:(GpsState*)state;
-(void)onFailure:(GpsState*)state withDescription:(NSString*)description;
@end

@interface GpsState : NSObject<CLLocationManagerDelegate>
- (void)update;

@property double longitude;
@property double latitude;
@property Boolean loaded;
- (id)initWithNotifier:(id<GpsStateDataLoadNotification>)notifier;
@end
