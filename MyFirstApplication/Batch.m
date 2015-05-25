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
    float _numChunksThreshold;
    uint _totalChunks;
    Boolean _totalChunksIsPreset;
    double _timeoutSeconds;
    ByteBuffer* _partialPacket;
    NSTimer* _timer;
    Boolean _hasOutput;
    id<BatchPerformanceInformation> _performanceDelegate;
}

- (void)onTimeout:(NSTimer*)timer {
    //NSLog(@"Timed out with chunks received: %ul and threshold: %ul", _chunksReceived, _numChunksThreshold);
    if(_totalChunks == 0) { // value not loaded yet.
        return;
    }
    
    uint integerNumChunksThreshold = _numChunksThreshold * (float)_totalChunks;
    
    float chunksReceivedPercentage = ((double)_chunksReceived) / ((double)_totalChunks);
    [_performanceDelegate onNewOutput:chunksReceivedPercentage];
    
    if(_chunksReceived >= integerNumChunksThreshold) {
        @synchronized(_partialPacket) {
            if(!_hasOutput) {
                [_outputSession onNewPacket:_partialPacket fromProtocol:UDP];
                _hasOutput = true;
            }
        }
    }
}

- (id)initWithOutputSession:(id<NewPacketDelegate>)outputSession chunkSize:(uint)chunkSize numChunks:(uint)numChunks andNumChunksThreshold:(float)numChunksThreshold andTimeoutSeconds:(double)timeoutSeconds andPerformanceInformaitonDelegate:(id<BatchPerformanceInformation>)performanceInformationDelegate {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunksReceived = 0;
        _numChunksThreshold = numChunksThreshold;
        _chunkSize = chunkSize;
        _totalChunks = numChunks;
        _totalChunksIsPreset = _totalChunks != 0;
        _partialPacket = [[ByteBuffer alloc] initWithSize:numChunks * chunkSize];
        [_partialPacket setUsedSize: [_partialPacket bufferMemorySize]];
        _timeoutSeconds = timeoutSeconds;
        _hasOutput = false;
        _performanceDelegate = performanceInformationDelegate;
        
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
    
    // Total chunks may be unknown, in which case each chunk also contains
    // a total chunks field.
    if(_totalChunks == 0) {
        _totalChunks = [packet getUnsignedInteger]; // use total chunks field.
    } else if(!_totalChunksIsPreset) {
        [packet getUnsignedInteger]; // discard total chunks field.
    }
    
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
