//
//  MediaController.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 07/01/2015.
//
//

#import "MediaByteBuffer.h"
#import "Encoding.h"
#import "OutputSessionTcp.h"
#import "MediaController.h"

@implementation MediaController {
    AVCaptureSession* _session;
    id<NewImageDelegate> _newImageDelegate;
    id<OutputSessionBase> _networkOutputSession;
    Encoding* _mediaEncoder;
}

- (id)initWithImageDelegate: (id<NewImageDelegate>)newImageDelegate andwithNetworkOutputSession: (id<OutputSessionBase>)networkOutputSession {
    self = [super init];
    if(self) {
        _networkOutputSession = networkOutputSession;
	    _newImageDelegate = newImageDelegate;

        _mediaEncoder = [[Encoding alloc] init];
        _session = [_mediaEncoder setupCaptureSessionWithDelegate: self];
    }
    return self;
}

- (void) startCapturing {
    [_session startRunning];
}

- (void) stopCapturing {
    [_session stopRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    bool connected = false;
    if(!connected) {
        // update display with no networking.
        UIImage *image = [_mediaEncoder imageFromSampleBuffer: sampleBuffer];
        [_newImageDelegate onNewImage: image];
    } else {
        // Send image as packet.
        ByteBuffer * rawBuffer = [[ByteBuffer alloc] init];
        MediaByteBuffer* buffer = [[MediaByteBuffer alloc] initFromBuffer: rawBuffer];
        [rawBuffer addUnsignedInteger:1];
        [buffer addImage: sampleBuffer];
        //[_networkOutputSession sendPacket: rawBuffer]; <- temporarily disabled.
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    // Update display with image retrieved from packet.
    MediaByteBuffer* buffer = [[MediaByteBuffer alloc] initFromBuffer: packet];
    UIImage *image = [buffer getImage];
    [_newImageDelegate onNewImage: image];
}

@end
