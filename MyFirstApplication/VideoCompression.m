//
//  VideoCompression.m
//  Spawn
//
//  Created by Michael Pryor on 03/01/2016.
//
//

#import "VideoCompression.h"
#import "libavformat/avformat.h"

@implementation VideoCompression
- (id)init {
    int result;

    av_register_all();

    AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (encoder == nil) {
        NSLog(@"Failed to find encoder");
    }

    struct AVCodecContext *context = avcodec_alloc_context3(encoder);
    if (context == nil) {
        NSLog(@"Failed to create context");
    }

    AVDictionary *codecOptions = nil;
    result = av_dict_set(&codecOptions, "preset", "medium", 0); // TODO: consider changing.
    if (result != 0) {
        NSLog(@"Failed to set 'preset' value of h248 encoder: %d", result);
    }

    result = av_dict_set(&codecOptions, "tune", "zerolatency", 0); // TODO: consider changing.
    if (result != 0) {
        NSLog(@"Failed to set 'tune' value of h248 encoder: %d", result);
    }

    // TODO: consider changing below settings.
    context->width = 512;
    context->height = 512;
    context->time_base = (AVRational) {1, 25};
    context->gop_size = 10;
    context->max_b_frames = 1;
    context->bit_rate = 400000;
    context->pix_fmt = AV_PIX_FMT_YUV420P;


    result = avcodec_open2(context, encoder, &codecOptions);
    if (result != 0) {
        NSLog(@"Failed to open av codec: %d", result);
    }

    AVFrame *picture = av_frame_alloc();


    // DECODING BELOW

    AVCodec *decoder = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (decoder == nil) {
        NSLog(@"Cannot find decoder");
    }

    AVProfile *profile = decoder->profiles;
    while (profile &&
            profile->profile != FF_PROFILE_UNKNOWN) {
        NSLog(@"Decoder profile name: %s", profile->name);
        profile++;
    }
    return self;
}
@end
