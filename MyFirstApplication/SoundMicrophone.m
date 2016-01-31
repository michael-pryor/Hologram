//
//  Encoding.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 04/01/2015.
//
//

#import "SoundMicrophone.h"
#import "SoundEncodingShared.h"
#import "Signal.h"
#import "BlockingQueue.h"
#import "Timer.h"


#define RESET_AFTER_NO_DATA_FOR_SECONDS 5

@import AudioToolbox;

@implementation SoundMicrophone {
    // Thread safe state.
    Signal *_isRecording;
    Signal *_queueSetup;
    Signal *_magicCookieLoaded;

    // Audio queue interactions.
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef *_audioBuffers;
    AudioStreamBasicDescription _audioDescription;

    // Magic cookie.
    Byte *_magicCookie;
    int _magicCookieSize;

    // Callback.
    id <NewPacketDelegate> _outputSession;

    // Thread.
    NSThread *_inputThread;
    NSThread *_bufferControllerThread;

    // Settings.
    uint _leftPadding;
    uint _numBuffers;
    UInt32 _bufferSizeBytes;

    volatile bool _stoppedExternally;
    volatile bool _initialEnqueueCompleted;

    BlockingQueue *_bufferPool;

    Timer *_successTracker;
}

- (id)initWithOutputSession:(id <NewPacketDelegate>)output numBuffers:(uint)numBuffers leftPadding:(uint)padding {
    self = [super init];
    if (self) {
        _magicCookie = nil;
        _outputSession = output;

        memset(&_audioDescription, 0, sizeof(_audioDescription));
        _audioDescription.mFormatID = kAudioFormatMPEG4AAC;
        _audioDescription.mChannelsPerFrame = 1;
        _audioDescription.mSampleRate = 8000.0;
        _audioDescription.mFramesPerPacket = 1024;

        _queueSetup = [[Signal alloc] initWithFlag:false];
        _isRecording = [[Signal alloc] initWithFlag:false];
        _magicCookieLoaded = [[Signal alloc] initWithFlag:false];

        _numBuffers = numBuffers;
        _leftPadding = padding;
        _audioBuffers = malloc(sizeof(AudioQueueBufferRef) * _numBuffers);
        _bufferSizeBytes = calculateBufferSize(&_audioDescription);

        _stoppedExternally = true;
        _initialEnqueueCompleted = false;

        _bufferPool = [[BlockingQueue alloc] init];
        [_bufferPool enableUniqueConstraint];

        _successTracker = [[Timer alloc] initWithFrequencySeconds:RESET_AFTER_NO_DATA_FOR_SECONDS firingInitially:false];
    }
    return self;
}

- (void)dealloc {
    [self stopCapturing:false];
    OSStatus result = AudioQueueDispose(_audioQueue, true);
    HandleResultOSStatus(result, @"Disposing of microphone queue", true);

    free(_audioBuffers);
    [_queueSetup clear];
}

- (bool)shouldAttemptEnqueue {
    return [_isRecording isSignaled] && [_queueSetup isSignaled];
}

- (bool)handleResultOsStatus:(OSStatus)result description:(NSString *)description {
    if (HandleResultOSStatus(result, description, true)) {
        return true;
    }

    [self stopCapturing:false];
    [self startCapturing:false];
    return false;
}

- (AudioQueueBufferRef)allocateBufferWithIndex:(int)index cleanup:(bool)doCleanup {
    if (doCleanup) {
        OSStatus result = AudioQueueFreeBuffer(_audioQueue, _audioBuffers[index]);
        if(!HandleResultOSStatus(result, @"Freeing bad microphone buffer", true)) {
            return nil;
        }
    }

    OSStatus result = AudioQueueAllocateBuffer(_audioQueue,
            _bufferSizeBytes,
            &_audioBuffers[index]);
    if(!HandleResultOSStatus(result, @"Allocating microphone buffer", true)) {
        return nil;
    }
    return _audioBuffers[index];
}

- (void)inputThreadEntryPoint:var {
    OSStatus result = AudioQueueNewInput(&_audioDescription,
            HandleInputBuffer,
            (__bridge void *) (self),
            CFRunLoopGetCurrent(),
            kCFRunLoopCommonModes,
            0, // Reserved, must be 0
            &_audioQueue);

    HandleResultOSStatus(result, @"Initializing microphone queue", true);

    // Allocate.
    for (int i = 0; i < _numBuffers; ++i) {
        [self allocateBufferWithIndex:i cleanup:false];
    }

    NSLog(@"Microphone thread initialized");
    [_queueSetup signalAll];

    CFRunLoopRun();
}

- (bool)enqueueBuffer:(AudioQueueBufferRef)buffer {
    OSStatus result = AudioQueueEnqueueBuffer(_audioQueue,
            buffer,
            0,
            NULL);

    // Do not restart queues on failure.
    return HandleResultOSStatus(result, @"Enqueing microphone buffer", false);
}

- (bool)enqueueBuffers {
    for (int i = 0; i < _numBuffers; ++i) {
        if (![self enqueueBuffer:_audioBuffers[i]]) {
            // Return those that were not queued back to pool.
            for (; i < _numBuffers; i++) {
                [self returnToPool:_audioBuffers[i]];
            }
            return false;
        }
    }
    return true;
}

- (Byte *)getMagicCookie {
    return _magicCookie;
}

- (int)getMagicCookieSize {
    return _magicCookieSize;
}

- (void)initialize {
    // Run send operations in a separate run loop (and thread) because we wait for packets to
    // enter a queue and block indefinitely, which would block anything else in the run loop (e.g.
    // receive operations) if there were some.
    _inputThread = [[NSThread alloc] initWithTarget:self
                                           selector:@selector(inputThreadEntryPoint:)
                                             object:nil];
    [_inputThread start];
    [_queueSetup wait];

    [self startCapturing];

    _bufferControllerThread = [[NSThread alloc] initWithTarget:self selector:@selector(bufferControllerThreadEntryPoint:) object:nil];
    [_bufferControllerThread start];

    NSLog(@"Microphone thread started");
}

- (void)bufferControllerThreadEntryPoint:(id)obj {
    bool running = true;

    [_successTracker reset];
    while (running) {
        // Wait for an available audio buffer.
        NSValue *_bufferVal = [_bufferPool getWithTimeout:RESET_AFTER_NO_DATA_FOR_SECONDS];
        if (_bufferVal == nil || [_successTracker getState]) {
            if (!_stoppedExternally) {
                NSLog(@"Resetting microphone because failed to succeed within %d seconds", RESET_AFTER_NO_DATA_FOR_SECONDS);
                [self stopCapturing:false];
                [self startCapturing:false];
            }
            continue;
        }

        // Extract value.
        AudioQueueBufferRef audioQueueBuffer;
        [_bufferVal getValue:&audioQueueBuffer];

        [_isRecording wait];

        bool errored = false;
        @synchronized (self) {
            if (![self enqueueBuffer:audioQueueBuffer]) {
                NSLog(@"Failed to enqueue buffer from buffer controller");
                [self returnToPool:audioQueueBuffer];
                errored = true;
            }
        }

        // We failed to enqueue, probably because operating system wasn't ready yet (if app was paused/resumed) or if
        // we very recently stopped the audio queue.
        if (errored) {
            float timeInterval = 0.1;
            NSLog(@"Waiting %.2f seconds before resuming microphone buffer controller thread (in response to failure)", timeInterval);
            [NSThread sleepForTimeInterval:timeInterval];
        } else {
            [_successTracker reset];
        }
    }
}

- (void)setOutputSession:(id <NewPacketDelegate>)output {
    _outputSession = output;
}

- (AudioStreamBasicDescription *)getAudioDescription {
    return &_audioDescription;
}

- (void)startCapturing {
    [self startCapturing:true];
}

- (void)stopCapturing {
    [self stopCapturing:true];
}

- (void)startCapturing:(bool)external {
    if (!external) {
        if (_stoppedExternally) {
            NSLog(@"Ignoring start capture attempt on microphone, externally stopped");
            return;
        }
    } else {
        if (_stoppedExternally) {
            NSLog(@"Resuming microphone audio capture externally called");
            _stoppedExternally = false;
        }
    }

    @synchronized (self) {
        if ([_queueSetup isSignaled] && [_isRecording signalAll]) {
            [self resetPool];

            OSStatus result = AudioQueueStart(_audioQueue, NULL);
            if (![self handleResultOsStatus:result description:@"Starting microphone queue"]) {
                return;
            }

            if (!_initialEnqueueCompleted) {
                _initialEnqueueCompleted = true;
                [self enqueueBuffers];
            }

            [_magicCookieLoaded wait];
        }
    }
}

- (void)stopCapturing:(bool)external {
    if (external) {
        if (!_stoppedExternally) {
            NSLog(@"Stopped microphone capture externally");
            _stoppedExternally = true;
        }
    } else {
        if (_stoppedExternally) {
            NSLog(@"Already stopped microphone capture externally");
            return;
        }
    }

    @synchronized (self) {
        if ([_queueSetup isSignaled] && [_isRecording clear]) {
            OSStatus result = AudioQueueFlush(_audioQueue);
            HandleResultOSStatus(result, @"Flushing the microphone queue", true);

            result = AudioQueueStop(_audioQueue, true);
            HandleResultOSStatus(result, @"Stopping the microphone queue", true);
        }
    }
}

- (id <NewPacketDelegate>)getOutputSession {
    return _outputSession;
}

- (uint)getLeftPadding {
    return _leftPadding;
}

static void HandleInputBuffer(void *aqData,
        AudioQueueRef inAQ,
        AudioQueueBufferRef inBuffer,
        const AudioTimeStamp *inStartTime,
        UInt32 inNumPackets,
        const AudioStreamPacketDescription *inPacketDesc) {
    SoundMicrophone *obj = (__bridge SoundMicrophone *) (aqData);
    uint leftPadding = [obj getLeftPadding];
    uint size = leftPadding + inBuffer->mAudioDataByteSize;

    if (inNumPackets == 0) {
        NSLog(@"0 packets received on audio input callback");
        [obj returnToPool:inBuffer];
        return;
    }

    if (inPacketDesc[0].mVariableFramesInPacket > 0) {
        NSLog(@"Variable frames");
    }

    if (inNumPackets > 1) {
        NSLog(@"More than one packet");
    }

    if (inPacketDesc[0].mStartOffset > 0) {
        NSLog(@"Start offset");
    }

    if (inPacketDesc[0].mDataByteSize != inBuffer->mAudioDataByteSize) {
        NSLog(@"Byte mismatch");
    }

    if (obj->_magicCookie == nil) {
        UInt32 propertySize;
        OSStatus status = AudioQueueGetPropertySize(obj->_audioQueue, kAudioConverterCompressionMagicCookie, &propertySize);
        if (![obj handleResultOsStatus:status description:@"Retrieving magic cookie size"]) {
            NSLog(@"Returning to pool");
            [obj returnToPool:inBuffer];
            [obj->_magicCookieLoaded dummySignalAll];
            return;
        }
        obj->_magicCookieSize = propertySize;

        obj->_magicCookie = (Byte *) malloc(propertySize);
        status = AudioQueueGetProperty(obj->_audioQueue, kAudioQueueProperty_MagicCookie, obj->_magicCookie, &propertySize);
        if (![obj handleResultOsStatus:status description:@"Retrieving magic cookie"]) {
            NSLog(@"Returning to pool");
            [obj returnToPool:inBuffer];
            [obj->_magicCookieLoaded dummySignalAll];
            return;
        }

        [obj->_magicCookieLoaded signalAll];
    }

    if (inBuffer->mAudioDataByteSize > 0) {
      //  NSLog(@"Packet has data %lu", inBuffer->mAudioDataByteSize);
        ByteBuffer *buff = [[ByteBuffer alloc] initWithSize:size];
        memcpy(buff.buffer + leftPadding, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        [buff setUsedSize:size];

        [[obj getOutputSession] onNewPacket:buff fromProtocol:UDP];
    } else {
        NSLog(@"Microphone generated empty buffer");
    }

    if ([obj->_isRecording isSignaled]) {
        //NSLog(@"Returning to pool");
        [obj returnToPool:inBuffer];
    } else {
        NSLog(@"Dropping from pool");
    }
}

// Return buffer to pool to be reused.
- (void)returnToPool:(AudioQueueBufferRef)audioBuffer {
    NSValue *nsValue = [NSValue value:&audioBuffer withObjCType:@encode(AudioQueueBufferRef)];
    [_bufferPool add:nsValue];
}


// Empty the pool and repopulate from scratch.
- (void)resetPool {
    @synchronized (self) {
        NSLog(@("Resetting the microphone pool"));
        [_bufferPool clear];
        for (int n = 0; n < _numBuffers; n++) {
            [self returnToPool:_audioBuffers[n]];
        }
    }
}


@end
