//
//  Encoding.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

@import AVFoundation;

@interface Encoding : NSObject
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer;
@end
