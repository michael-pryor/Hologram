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
#import "BatcherInput.h"
#import "BatcherOutput.h"

@implementation MediaController {
    AVCaptureSession* _session;
    id<NewImageDelegate> _newImageDelegate;
    id<OutputSessionBase> _networkOutputSession;
    Encoding* _mediaEncoder;
    BatcherInput* _batcherInput;
    BatcherOutput* _batcherOutput;
    
    bool _connected;
}

- (id)initWithImageDelegate:(id<NewImageDelegate>)newImageDelegate andwithNetworkOutputSession:(id<OutputSessionBase>)networkOutputSession {
    self = [super init];
    if(self) {
        _networkOutputSession = networkOutputSession;
	    _newImageDelegate = newImageDelegate;

        _mediaEncoder = [[Encoding alloc] init];
        _session = [_mediaEncoder setupCaptureSessionWithDelegate: self];

        _batcherOutput = [[BatcherOutput alloc] initWithOutputSession:self andChunkSize:1024];
        _batcherInput = [[BatcherInput alloc] initWithOutputSession:self chunkSize:1024 numChunks:80 andNumChunksThreshold:70 andTimeoutMs:1000];
        
        _connected = false;
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
    if(!_connected) {
        // update display with no networking.
        UIImage *image = [_mediaEncoder imageFromSampleBuffer: sampleBuffer];
        [_newImageDelegate onNewImage: image];
    } else {
        // Send image as packet.
        ByteBuffer * rawBuffer = [[ByteBuffer alloc] init];
        MediaByteBuffer* buffer = [[MediaByteBuffer alloc] initFromBuffer: rawBuffer];
        [rawBuffer addUnsignedInteger:1];
        [buffer addImage: sampleBuffer];
        [_networkOutputSession sendPacket: rawBuffer];
    }
}

- (void)onNewPacket:(ByteBuffer *)packet fromProtocol:(ProtocolType)protocol {
    // Update display with image retrieved from packet.
    MediaByteBuffer* buffer = [[MediaByteBuffer alloc] initFromBuffer: packet];
    UIImage *image = [buffer getImage];
    [_newImageDelegate onNewImage: image];
}

- (void)connectionStatusChange:(ConnectionStatusProtocol)status withDescription:(NSString *)description {
    _connected = status == P_CONNECTED;
}

@end
