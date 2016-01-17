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
#import "VideoOutputController.h"
#import "Orientation.h"

// Handle endianness
#define clamp(a) (a>255?255:(a<0?0:a))

#define ALIGN_TO_BITS 32

// For cleanup:
// Use av_frame_free
// Use av_packet_unref
@implementation VideoCompression {
    AVCodec *_codecEncoder;
    struct AVCodecContext *codecEncoderContext;

    AVCodec *_codecDecoder;
    struct AVCodecContext *codecDecoderContext;

    CVPixelBufferPoolRef _pixelBufferPool;
    UIImageOrientation _imageOrientation;
}
- (id)init {
    self = [super init];
    if (self) {
        int result;

        av_register_all();

        {
            CVReturn cvResult = CVPixelBufferPoolCreate(nil,
                    (__bridge CFDictionaryRef _Nullable) (@{(id) kCVPixelBufferPoolMinimumBufferCountKey : @5}),
                    (__bridge CFDictionaryRef _Nullable) (@{(id) kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
                            (id) kCVPixelBufferWidthKey : [NSNumber numberWithUnsignedInt:(uint) 640],
                            (id) kCVPixelBufferHeightKey : [NSNumber numberWithUnsignedInt:(uint) 480],
                            (id) kCVPixelBufferIOSurfacePropertiesKey : @{}}),
                    &_pixelBufferPool);


            if (cvResult != kCVReturnSuccess) {
                NSLog(@"CVPixelBufferPoolCreate failed, error code: %d", cvResult);
            }
        }

        {
            _codecEncoder = avcodec_find_encoder(AV_CODEC_ID_H264);
            if (_codecEncoder == nil) {
                NSLog(@"Failed to find encoder");
            }

            codecEncoderContext = avcodec_alloc_context3(_codecEncoder);
            if (codecEncoderContext == nil) {
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
            codecEncoderContext->width = 640;
            codecEncoderContext->height = 480; // based on settings used when setting up AVCapture (not ffmpeg, but the actual iOS interactions).
            codecEncoderContext->time_base = (AVRational) {1, 25};
            codecEncoderContext->gop_size = 10;
            codecEncoderContext->max_b_frames = 1;
            codecEncoderContext->bit_rate = 400000;
            codecEncoderContext->pix_fmt = AV_PIX_FMT_YUV420P;


            result = avcodec_open2(codecEncoderContext, _codecEncoder, &codecOptions);
            if (result != 0) {
                NSLog(@"Failed to open av codec: %d", result);
            }
        }

        {
            // DECODING BELOW

            _codecDecoder = avcodec_find_decoder(AV_CODEC_ID_H264);
            if (_codecDecoder == nil) {
                NSLog(@"Cannot find decoder");
            }

            codecDecoderContext = avcodec_alloc_context3(_codecDecoder);
            if (codecDecoderContext == nil) {
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
            codecDecoderContext->width = 640;
            codecDecoderContext->height = 480; // based on settings used when setting up AVCapture (not ffmpeg, but the actual iOS interactions).
            codecDecoderContext->time_base = (AVRational) {1, 25};
            codecDecoderContext->gop_size = 10;
            codecDecoderContext->max_b_frames = 1;
            codecDecoderContext->bit_rate = 400000;
            codecDecoderContext->pix_fmt = AV_PIX_FMT_YUV420P;


            result = avcodec_open2(codecDecoderContext, _codecDecoder, &codecOptions);
            if (result != 0) {
                NSLog(@"Failed to open av codec: %d", result);
            }
        }

        [Orientation registerForOrientationChangeNotificationsWithObject:self selector:@selector(onOrientationChange:)];
        [self onOrientationChange:nil];
    }
    return self;
}


- (void)onOrientationChange:(NSNotification *)notification {
    UIInterfaceOrientation orientation = [Orientation getDeviceOrientation];

    _imageOrientation = UIImageOrientationLeft;
    switch(orientation) {
        case UIInterfaceOrientationLandscapeRight:
        case UIInterfaceOrientationLandscapeLeft:
            _imageOrientation = UIImageOrientationDown;
            break;

        case UIInterfaceOrientationPortrait:
        case UIInterfaceOrientationPortraitUpsideDown:
        case UIInterfaceOrientationUnknown:
        default:
            _imageOrientation = UIImageOrientationLeft;
            break;
    }
}

- (UIImage *)convertYuvFrameToImage:(AVFrame *)frame {
    size_t width = (size_t) frame->width;
    size_t height = (size_t) frame->height;

    CVPixelBufferRef pixelBuffer = NULL;

    CVReturn result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
            _pixelBufferPool,
            &pixelBuffer);
    if (result != kCVReturnSuccess) {
        NSLog(@"CVPixelBufferPoolCreatePixelBuffer failed, error code: %d", result);
        return nil;
    }

    size_t yComponentSizeBytes = width * height;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    // y plane.
    unsigned char *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    memcpy(yDestPlane, frame->data[0], yComponentSizeBytes);

    // uv (cb cr) plane.
    unsigned char *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);

    // Copy Cr and Cb component into ffmpeg structure.
    // Divide by 2 on y because half as many rows in cbCr as Y.
    for (int y = 0; y < height / 2; y++) {
        uint8_t *cbCrBufferLine = &uvDestPlane[y * width];

        // Divide by 2 on x because width is half in cbCr vs Y.
        for (int x = 0; x < width / 2; x++) {
            // when xMultTwo is 0, cbIndex is 0, crIndex is 1
            // when xMultTwo is 1, cbIndex is 0, crIndex is 1
            // when xMultTwo is 2, cbIndex is 2, crIndex is 3
            // when xMultTwo is 3, cbIndex is 2, crIndex is 3
            // when xMultTwo is 4, cbIndex is 4, crIndex is 5
            // ...
            int xMultTwo = x * 2;
            int cbIndex = xMultTwo & ~1;
            int crIndex = xMultTwo | 1;

            // Divide by 2 because each buffer takes half of the contents (one for cb, one for cr).
            size_t theIndex = (y * (width / 2)) + x;
            uint8_t cb = frame->data[1][theIndex];
            uint8_t cr = frame->data[2][theIndex];

            cbCrBufferLine[cbIndex] = cb;
            cbCrBufferLine[crIndex] = cr;
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    CIImage *coreImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];

    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [context
            createCGImage:coreImage
                 fromRect:CGRectMake(0, 0,
                         width,
                         height)];

    UIImage *imageResult = [[UIImage alloc] initWithCGImage:videoImage scale:1.0 orientation:_imageOrientation];

    CGImageRelease(videoImage);
    CVPixelBufferRelease(pixelBuffer);

    return imageResult;
}

// This takes h264 packets and produces:
// AVFrame objects, which have 3 byte buffers loaded with:
// 1: Y values (brightness, white/black, luma) - data size matches size of image.
// 2: Cb values (blue) - data num rows = rows of image, width = half of image width.
// 3: Cr values (red) - data num rows = rows of image, width = half of image width.
//
// To use this with iOS, we need to convert to UIImage.
- (AVFrame *)decodeToYuvFromData:(uint8_t *)data andSize:(int)size {
    // Store the item to be decoded (input).
    struct AVPacket packet;
    av_init_packet(&packet);

    packet.data = data;
    packet.size = size;

    // The decoder will populate the decoded result into this frame (output).
    AVFrame *picture = av_frame_alloc();
    if (picture == nil) {
        NSLog(@"Failed av_frame_alloc");
        av_packet_unref(&packet);
        return nil;
    }

    int gotOutput;

    // Allocates memory to 'picture', memory is owned by codec so we simply unref it to say that
    // we are done with it. Do not free the actual allocated memory.
    int result = avcodec_decode_video2(codecDecoderContext, picture, &gotOutput, &packet);
    if (result <= 0) {
        NSLog(@"Failed avcodec_decode_video2: %d", result);
        av_packet_unref(&packet);
        av_frame_free(&picture);
        return nil;
    }

    if (gotOutput) {
        int resultImageSizeBytes = av_image_get_buffer_size(codecDecoderContext->pix_fmt, codecDecoderContext->width, codecDecoderContext->height, ALIGN_TO_BITS);
        NSLog(@"Retrieved YUV image of size: %d, bytes written: %d", resultImageSizeBytes, result);

        av_packet_unref(&packet);
        return picture;
    } else {
        NSLog(@"We didn't get any data from the decoder");
        av_packet_unref(&packet);
        av_frame_free(&picture);
        return nil;
    }
}

- (void)freeYuvFrame:(AVFrame *)picture {
    // Only one buffer is allocated but elements 1 and 2 reference parts of that buffer,
    // so only free once.
    av_freep(&picture->data[0]);
    picture->data[1] = nil;
    picture->data[2] = nil;
    av_frame_free(&picture);
}

// Encodes the packet
- (bool)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer toByteBuffer:(ByteBuffer *)buffer {
    int result;

    // SO basically.
    // iOS gives us CMSampleBuffer, in this there are two planar:
    // 1. Y values
    // 2. CbCr values, presumably aligned CbCrCbCrCbCr.
    //
    // ffmpeg/avcodec gives us a AVFrame object with which to load with data.
    // This has 3 byte buffers which should be loaded with:
    // 1: Y values (brightness, white/black, luma) - data size matches size of image.
    // 2: Cb values (blue) - data num rows = rows of image, width = half of image width.
    // 3: Cr values (red) - data num rows = rows of image, width = half of image width.

    // Picture containing data to be encoded (input).
    AVFrame *picture = av_frame_alloc();
    if (picture == nil) {
        NSLog(@"Failed av_frame_alloc");
        return false;
    }

    int pictureByteSize = av_image_alloc(picture->data, picture->linesize, codecEncoderContext->width, codecEncoderContext->height, codecEncoderContext->pix_fmt, ALIGN_TO_BITS);
    if (pictureByteSize < 0) {
        NSLog(@"Failed av_image_alloc: %d", pictureByteSize);
        return false;
    }

    picture->format = codecEncoderContext->pix_fmt;
    picture->width = codecEncoderContext->width;
    picture->height = codecEncoderContext->height;

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    // Convert from iOS to ffmpeg/AVcodec.
    uint8_t *yBuffer = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *cbCrBuffer = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);

    size_t yComponentBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    size_t yComponentHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);

    size_t cbCrComponentBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    size_t cbCrComponentHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);

    // Copy Y component into ffmpeg structure.
    size_t yComponentTotalBytes = yComponentHeight * yComponentBytesPerRow;
    memcpy(picture->data[0], yBuffer, yComponentTotalBytes);

    // Copy Cr and Cb component into ffmpeg structure.
    for (int y = 0; y < cbCrComponentHeight; y++) {
        uint8_t *cbCrBufferLine = &cbCrBuffer[y * cbCrComponentBytesPerRow];

        // Divide by 2 on x because width is half in cbCr vs Y.
        for (int x = 0; x < cbCrComponentBytesPerRow / 2; x++) {
            // when xMultTwo is 0, cbIndex is 0, crIndex is 1
            // when xMultTwo is 1, cbIndex is 0, crIndex is 1
            // when xMultTwo is 2, cbIndex is 2, crIndex is 3
            // when xMultTwo is 3, cbIndex is 2, crIndex is 3
            // when xMultTwo is 4, cbIndex is 4, crIndex is 5
            // ...
            int xMultTwo = x * 2;
            int cbIndex = xMultTwo & ~1;
            int crIndex = xMultTwo | 1;

            uint8_t cb = cbCrBufferLine[cbIndex];
            uint8_t cr = cbCrBufferLine[crIndex];

            // Divide by 2 because each buffer takes half of the contents (one for cb, one for cr).
            size_t theIndex = (y * (cbCrComponentBytesPerRow / 2)) + x;
            picture->data[1][theIndex] = cb;
            picture->data[2][theIndex] = cr;
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    // Packet to be allocated by the encoder (will contain output).
    AVPacket packet;
    av_init_packet(&packet);

    packet.data = nil;
    packet.size = 0;

    // Do the encoding.
    int gotOutput;
    result = avcodec_encode_video2(codecEncoderContext, &packet, picture, &gotOutput);

    [self freeYuvFrame:picture];

    if (result != 0) {
        NSLog(@"Failed avcodec_encode_video: %d", result);
        return false;
    }

    if (gotOutput) {
        NSLog(@"We got some data from the encoder, be proud, with size: %d", packet.size);
        [buffer addVariableLengthData:packet.data withLength:(uint) packet.size includingPrefix:false];
        av_packet_unref(&packet);

        return true;
    } else {
        NSLog(@"We didn't get any data from the encoder");
        // packet is freed automatically by avcodec_encode_video2 if no data returned.

        return false;
    }
}

- (UIImage *)decodeByteBuffer:(ByteBuffer *)buffer {
    AVFrame *decodedYuv = [self decodeToYuvFromData:buffer.buffer + buffer.cursorPosition andSize:buffer.bufferUsedSize];

    if (decodedYuv == nil) {
        return nil;
    }

    UIImage *image = [self convertYuvFrameToImage:decodedYuv];
    av_frame_free(&decodedYuv);

    // May be null.
    return image;
}


@end