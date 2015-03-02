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
    uint _totalChunks;
    double _timeoutSeconds;
    ByteBuffer* _partialPacket;
    NSTimer* _timer;
    Boolean _hasOutput;
}

- (void)onTimeout:(NSTimer*)timer {
    NSLog(@"Timed out with chunks received: %ul and threshold: %ul", _chunksReceived, _numChunksThreshold);
    if(_chunksReceived >= _numChunksThreshold) {
        @synchronized(_partialPacket) {
            if(!_hasOutput) {
                [_outputSession onNewPacket:_partialPacket fromProtocol:UDP];
                _hasOutput = true;
            }
        }
    }
}

- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(uint)numChunksThreshold andTimeoutSeconds:(double)timeoutSeconds {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunksReceived = 0;
        _numChunksThreshold = numChunksThreshold;
        _chunkSize = chunkSize;
        _totalChunks = numChunks;
        _partialPacket = [[ByteBuffer alloc] initWithSize:numChunks * chunkSize];
        [_partialPacket setUsedSize: [_partialPacket bufferMemorySize]];
        _timeoutSeconds = timeoutSeconds;
        _hasOutput = false;
        
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
    _chunksReceived += 1;
    
    uint chunkId = [packet getUnsignedInteger];
    uint buffPosition = [self getBufferPositionFromChunkId: chunkId];
    
    // Copy contents of chunk packet into partial packet.
    Boolean fireNow = false; // optimization to avoid locking when timer fires.
    @synchronized(_partialPacket) {
        if(!_hasOutput) {
            [_partialPacket addByteBuffer:packet includingPrefix:false atPosition:buffPosition startingFrom:[packet cursorPosition]];
            
            if(_chunksReceived == _totalChunks) {
                fireNow = true;
            }
        }
    }
    if(fireNow) {
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [_timer fire];
        });
    }
}

@end
