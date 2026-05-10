#import "OpusDecoderBridge.h"
#import <opus.h>

@interface OpusDecoderBridge ()
@property (nonatomic, assign) OpusDecoder *decoder;
@property (nonatomic, assign) int sampleRate;
@property (nonatomic, assign) int channels;
@property (nonatomic, copy, nullable, readwrite) NSString *lastError;
@end

@implementation OpusDecoderBridge

- (instancetype)initWithSampleRate:(int)sampleRate channels:(int)channels {
    self = [super init];
    if (!self) {
        return nil;
    }
    _sampleRate = sampleRate;
    _channels = channels;
    [self createDecoder];
    return self;
}

- (void)dealloc {
    if (_decoder) {
        opus_decoder_destroy(_decoder);
        _decoder = NULL;
    }
}

- (void)reset {
    if (_decoder) {
        opus_decoder_destroy(_decoder);
        _decoder = NULL;
    }
    [self createDecoder];
}

- (nullable NSData *)decodePacket:(NSData *)packet {
    if (!_decoder) {
        [self createDecoder];
    }
    if (!_decoder || packet.length == 0) {
        return nil;
    }

    const int maxFrameSize = (_sampleRate / 1000) * 120;
    NSMutableData *pcm = [NSMutableData dataWithLength:maxFrameSize * _channels * sizeof(opus_int16)];
    int decodedSamples = opus_decode(
        _decoder,
        packet.bytes,
        (opus_int32)packet.length,
        (opus_int16 *)pcm.mutableBytes,
        maxFrameSize,
        0
    );

    if (decodedSamples < 0) {
        self.lastError = [NSString stringWithUTF8String:opus_strerror(decodedSamples)];
        return nil;
    }

    pcm.length = decodedSamples * _channels * sizeof(opus_int16);
    self.lastError = nil;
    return pcm;
}

- (void)createDecoder {
    int error = OPUS_OK;
    _decoder = opus_decoder_create(_sampleRate, _channels, &error);
    if (error != OPUS_OK) {
        self.lastError = [NSString stringWithUTF8String:opus_strerror(error)];
        _decoder = NULL;
    } else {
        self.lastError = nil;
    }
}

@end
