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

// Handle endianness
#define clamp(a) (a>255?255:(a<0?0:a))

#define ALIGN_TO_BITS 32

@implementation VideoCompression {
    AVCodec *codecEncoder;
    struct AVCodecContext *codecEncoderContext;

    AVCodec *codecDecoder;
    struct AVCodecContext *codecDecoderContext;

    id <NewImageDelegate> _newImageDelegate;
}
- (id)initWithNewImageDelegate:(id <NewImageDelegate>)newImageDelegate {
    self = [super init];
    if (self) {
        int result;

        av_register_all();

        _newImageDelegate = newImageDelegate;

        {
            codecEncoder = avcodec_find_encoder(AV_CODEC_ID_H264);
            if (codecEncoder == nil) {
                NSLog(@"Failed to find encoder");
            }

            codecEncoderContext = avcodec_alloc_context3(codecEncoder);
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


            result = avcodec_open2(codecEncoderContext, codecEncoder, &codecOptions);
            if (result != 0) {
                NSLog(@"Failed to open av codec: %d", result);
            }
        }

        {
            // DECODING BELOW

            codecDecoder = avcodec_find_decoder(AV_CODEC_ID_H264);
            if (codecDecoder == nil) {
                NSLog(@"Cannot find decoder");
            }

            codecDecoderContext = avcodec_alloc_context3(codecDecoder);
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


            result = avcodec_open2(codecDecoderContext, codecDecoder, &codecOptions);
            if (result != 0) {
                NSLog(@"Failed to open av codec: %d", result);
            }
        }


    }
    return self;
}

- (uint8_t *)convertYuvToRgb:(AVFrame *)frame {
    int width = frame->width;
    int height = frame->height;

    uint8_t *rgbBuffer = malloc(sizeof(uint8_t) * width * height * 4);

    for (int yOrig = 0; yOrig < frame->height; yOrig++) {
        for (int xOrig = 0; xOrig < frame->width; xOrig++) {
            // Y component
            const unsigned char yComponent = frame->data[0][frame->linesize[0] * yOrig + xOrig];

            // U, V components
            int x = xOrig / 2;
            int y = yOrig / 2;
            const unsigned char cb = frame->data[1][frame->linesize[1] * y + x];  // Cb
            const unsigned char cr = frame->data[2][frame->linesize[2] * y + x];  // Cr

            // RGB conversion
            const unsigned char r = yComponent + 1.402 * (cr - 128);
            const unsigned char g = yComponent - 0.344 * (cb - 128) - 0.714 * (cr - 128);
            const unsigned char b = yComponent + 1.772 * (cb - 128);

            int offset = (xOrig * 4) + (yOrig * width * 4);
            rgbBuffer[offset] = r;
            rgbBuffer[offset + 1] = g;
            rgbBuffer[offset + 2] = b;
            rgbBuffer[offset + 3] = UINT8_MAX; // alpha
        }
    }

    return rgbBuffer;
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
        return nil;
    }

    int gotOutput;

    int result = avcodec_decode_video2(codecDecoderContext, picture, &gotOutput, &packet);
    if (result <= 0) {
        NSLog(@"Failed avcodec_decode_video2: %d", result);
        return nil;
    }

    if (gotOutput) {
        int resultImageSizeBytes = av_image_get_buffer_size(codecDecoderContext->pix_fmt, codecDecoderContext->width, codecDecoderContext->height, ALIGN_TO_BITS);

        NSLog(@"Retrieved RGB image of size: %d, bytes written: %d", resultImageSizeBytes, result);

        av_packet_unref(&packet);
        return picture;
    } else {
        NSLog(@"We didn't get any data from the decoder");
        av_packet_unref(&packet);
    }
    return nil;
}

- (UIImage *)buildImageFromRgbBytes:(uint8_t *)bytes {
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress;

    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = codecDecoderContext->width * 4; // includes alpha.
    // Get the pixel buffer width and height
    size_t width = codecDecoderContext->width;
    size_t height = codecDecoderContext->height;

    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8,
            bytesPerRow, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast);
    baseAddress = CGBitmapContextGetData(context);

    memcpy(baseAddress, bytes, bytesPerRow * height);

    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];


    // Release the Quartz image
    CGImageRelease(quartzImage);
    return image;
}

// Encodes the packet
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
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
        return;
    }

    int pictureByteSize = av_image_alloc(picture->data, picture->linesize, codecEncoderContext->width, codecEncoderContext->height, codecEncoderContext->pix_fmt, ALIGN_TO_BITS);
    if (pictureByteSize < 0) {
        NSLog(@"Failed av_image_alloc: %d", pictureByteSize);
        return;
    }

    picture->format = codecEncoderContext->pix_fmt;
    picture->width = codecEncoderContext->width;
    picture->height = codecEncoderContext->height;

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    // Convert from iOS to ffmpeg/AVcodec.
    uint8_t *yBuffer = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *cbCrBuffer = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);

    // 640
    size_t yComponentBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);

    // 320 cb, 320 cr (total 640).
    // Row = width.
    size_t cbCrComponentBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);

    // 480
    int numRows = picture->height;

    size_t yComponentTotalBytes = numRows * yComponentBytesPerRow;

    // 1 Cr & Cb sample per 2x2 Y samples.
    // half the number of rows, half the pitch (width).
    size_t cbCrTotalBytes = (numRows * cbCrComponentBytesPerRow) / 2;

    size_t totalBytes = yComponentTotalBytes + cbCrTotalBytes;

    size_t cbBytesPerRow = cbCrComponentBytesPerRow / 2;

    // Copy Y component into ffmpeg structure.
    memcpy(picture->data[0], yBuffer, yComponentTotalBytes);

    // Copy Cr and Cb component into ffmpeg structure.
    for (int y = 0; y < numRows; y++) {
        // so if y is 1 then use index 0
        // y = 2, use 1
        // y = 3, use 1
        // y = 4, use 2
        // y = 5, use 2
        // y = 6, use 3

        if (y % 2 != 0) {
            continue;
        }

        uint8_t *cbCrBufferLine = &cbCrBuffer[(y/2) * cbCrComponentBytesPerRow];

        for (int x = 0; x < cbCrComponentBytesPerRow; x++) {
            if (x % 2 != 0) {
                continue;
            }

            // when x is 0, cbIndex is 0, crIndex is 1
            // when x is 1, cbIndex is 0, crIndex is 1
            // when x is 2, cbIndex is 2, crIndex is 3
            // when x is 3, cbIndex is 2, crIndex is 3
            // when x is 4, cbIndex is 4, crIndex is 5
            // ...
            int cbIndex = x & ~1;
            int crIndex = x | 1;

           // int cbIndex = y;
           // int crIndex = (picture->height / 2) + y;

            uint8_t cb = cbCrBufferLine[cbIndex];
            uint8_t cr = cbCrBufferLine[crIndex];

            // Divide by 2 because each buffer takes half of the contents (one for cb, one for cr).
            // Divide by 2 again because half rows of images (1 cb/cr for 2x2 y).
            // Divide by 2 on x because of iterating pattern of x.
            size_t theIndex = (y * (cbCrComponentBytesPerRow / 4)) + (x / 2);
            picture->data[1][theIndex] = cb;
            picture->data[2][theIndex] = cr;

            //NSLog(@"The index is: %lu", theIndex);
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
    if (result != 0) {
        NSLog(@"Failed avcodec_encode_video: %d", result);
    }

    if (gotOutput) {
        NSLog(@"We got some data from the encoder, be proud, with size: %d", packet.size);

        AVFrame *decodedYuv = [self decodeToYuvFromData:packet.data andSize:packet.size];

        if (decodedYuv != nil) {
            uint8_t *decodedRgb = [self convertYuvToRgb:picture]; // picture = not gone through encoder, decodedYuv = gone through encoder.
            UIImage * image = [self buildImageFromRgbBytes:decodedRgb];
            if (image != nil) {
                NSLog(@"NEW IMAGE LOADED");
                [_newImageDelegate onNewImage:image];
            }
            av_free(decodedYuv);
        }
    } else {
        NSLog(@"We didn't get any data from the encoder");
    }

    av_packet_unref(&packet);
    av_frame_unref(picture);

}


@end
