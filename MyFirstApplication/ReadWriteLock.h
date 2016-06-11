//
// Created by Michael Pryor on 11/06/2016.
//

#import <Foundation/Foundation.h>


@interface ReadWriteLock : NSObject
- (id)init;

- (void)lockForReading;

- (void)lockForWriting;

- (void)unlock;
@end