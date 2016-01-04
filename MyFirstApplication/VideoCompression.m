//
//  VideoCompression.m
//  Spawn
//
//  Created by Michael Pryor on 03/01/2016.
//
//

#import "VideoCompression.h"
#import "libavformat/avformat.h"
#import "libavutil/imgutils.h"

@implementation VideoCompression {
    AVCodec *codecEncoder;
    struct AVCodecContext *codecContext;
}
- (id)init {
    self = [super init];
    if (self) {
        int result;

        av_register_all();

        codecEncoder = avcodec_find_encoder(AV_CODEC_ID_H264);
        if (codecEncoder == nil) {
            NSLog(@"Failed to find encoder");
        }

        codecContext = avcodec_alloc_context3(codecEncoder);
        if (codecContext == nil) {
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
        codecContext->width = 640;
        codecContext->height = 480; // based on settings used when setting up AVCapture (not ffmpeg, but the actual iOS interactions).
        codecContext->time_base = (AVRational) {1, 25};
        codecContext->gop_size = 10;
        codecContext->max_b_frames = 1;
        codecContext->bit_rate = 400000;
        codecContext->pix_fmt = AV_PIX_FMT_YUV420P;


        result = avcodec_open2(codecContext, codecEncoder, &codecOptions);
        if (result != 0) {
            NSLog(@"Failed to open av codec: %d", result);
        }


        /*
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
        }*/
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    int result;

    // Picture containing data to be encoded (input).
    AVFrame *picture = av_frame_alloc();
    if (picture == nil) {
        NSLog(@"Failed av_frame_alloc");
        return;
    }

    int pictureByteSize = av_image_alloc(picture->data, picture->linesize, codecContext->width, codecContext->height, codecContext->pix_fmt, 32);
    if (pictureByteSize < 0) {
        NSLog(@"Failed av_image_alloc: %d", pictureByteSize);
        return;
    }

    picture->format = codecContext->pix_fmt;
    picture->width = codecContext->width;
    picture->height = codecContext->height;

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    unsigned int size = CVPixelBufferGetDataSize(pixelBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char * rawPixels = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);

    if (size != pictureByteSize) {
        NSLog(@"Size of input picture (%d) is different to what encoder expects (%d)", size, pictureByteSize);
    }

    memcpy(picture->data[0], rawPixels, pictureByteSize);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    // Packet to be allocated by the encoder (will contain output).
    AVPacket packet;
    av_init_packet(&packet);

    packet.data = nil;
    packet.size = 0;

    // Do the encoding.
    int gotOutput;
    result = avcodec_encode_video2(codecContext, &packet, picture, &gotOutput);
    if (result != 0) {
        NSLog(@"Failed avcodec_encode_video: %d", result);
    }

    if (gotOutput) {
        NSLog(@"We got some data from the encoder, be proud");
        av_packet_unref(&packet);
    } else {
        NSLog(@"We didn't get any data from the encoder");
    }
}

@end
