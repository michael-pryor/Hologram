//
//  VideoCompression.m
//  Spawn
//
//  Created by Michael Pryor on 03/01/2016.
//
//

#import "VideoCompression.h"
#include "x264_config.h"
#include "x264.h"
#import "libavformat/avformat.h"
#import "libavcodec/avcodec.h"


@implementation VideoCompression
- (id)init {
    av_register_all();

    AVCodec * encoder = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (encoder == nil) {
        NSLog(@"Failed to find encoder");
    }
    
    AVCodec * decoder = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (decoder == nil) {
        NSLog(@"Cannot find decoder");
    }

    AVProfile *profile = decoder->profiles;
    while (profile &&
            profile->profile!=FF_PROFILE_UNKNOWN){
        NSLog(@"Decoder profile name: %s",profile->name);
        profile++;
    }
    return self;
}
@end
