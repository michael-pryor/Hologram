//
// Created by Michael Pryor on 21/01/2016.
//

#import <Foundation/Foundation.h>


@interface BatchSizeGenerator : NSObject
@property (readonly) uint desiredBatchSize;

- (id)initWithDesiredBatchSize:(uint)desiredBatchSize minimum:(uint)minimumBatchSizeThreshold maximum:(uint)maximiumBatchSizeThreshold maximumPacketSize:(uint)maximumPacketSize;

- (uint)getBatchSize:(uint)packetSize;

- (uint)getLastBatchSize:(uint)packetSize;
@end