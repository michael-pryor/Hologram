//
//  BatcherInput.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 14/02/2015.
//
//

#import "BatcherInput.h"

@implementation BatcherInput {
    uint _chunkSize;
    uint _batchId;
}
- (id)initWithOutputSession:(id<OutputSessionBase>)outputSession andChunkSize:(uint)chunkSize {
    self = [super initWithOutputSession:outputSession];
    if(self) {
        _chunkSize = chunkSize;
        _batchId = 0;
    }
    return self;
}
- (void)onNewPacket:(ByteBuffer*)packet fromProtocol:(ProtocolType)protocol {
    //  ************* we were midway through this and then got tired, scrap everything below *************
    uint batchSize = [packet bufferUsedSize];
    
    // Enough space to do something meaningful.
    ByteBuffer* buffer = [[ByteBuffer alloc] initWithSize:(_chunkSize + sizeof(uint) * 2)];
    
    [buffer addUnsignedInteger:batchId]; // batch ID.
    [buffer addUnsignedInteger:chunkId]; // chunk ID; ID within batch.
    
    // TODO: inefficiencies here copying buffers around and allocating memory.
    [buffer addByteBuffer: [batchPacket getByteBufferWithLength:_chunkSize] includingPrefix:false];
    
    return buffer;
}


@end
