//
//  BatcherInputBatch.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 22/02/2015.
//
//

#import "Batch.h"
#import "ByteBuffer.h"

@implementation Batch {
    uint _chunksReceived;
    uint _chunkSize;
    uint _numChunksThreshold;
    double _timeoutSeconds;
    ByteBuffer* _partialPacket;
    NSTimer* _timer;
}

- (void)onTimeout:(NSTimer*)timer {
    NSLog(@"Timed out with chunks received: %ul and threshold: %ul", _chunksReceived, _numChunksThreshold);
    if(_chunksReceived >= _numChunksThreshold) {
        @synchronized(_partialPacket) {
            [_outputSession onNewPacket:_partialPacket fromProtocol:UDP];
        }
    }
}

- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(uint)numChunksThreshold andTimeoutSeconds:(double)timeoutSeconds {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunksReceived = 0;
        _numChunksThreshold = numChunksThreshold;
        _chunkSize = chunkSize;
        _partialPacket = [[ByteBuffer alloc] initWithSize:numChunks * chunkSize];
        [_partialPacket setUsedSize: [_partialPacket bufferMemorySize]];
        _timeoutSeconds = timeoutSeconds;
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            _timer = [NSTimer scheduledTimerWithTimeInterval:_timeoutSeconds target:self selector:@selector(onTimeout:) userInfo:nil repeats:NO];
        });
    }
    return self;
}

- (uint)getBufferPositionFromChunkId: (uint)chunkId {
    return chunkId * _chunkSize;
}

- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    uint chunkId = [packet getUnsignedInteger];
    uint buffPosition = [self getBufferPositionFromChunkId: chunkId];
    
    // Copy contents of chunk packet into partial packet.
    @synchronized(_partialPacket) {
        [_partialPacket addByteBuffer:packet includingPrefix:false atPosition:buffPosition startingFrom:[packet cursorPosition]];
    }
    
    _chunksReceived += 1;
}

@end
