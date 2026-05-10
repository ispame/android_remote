#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpusDecoderBridge : NSObject

@property (nonatomic, copy, nullable, readonly) NSString *lastError;

- (instancetype)initWithSampleRate:(int)sampleRate channels:(int)channels;
- (nullable NSData *)decodePacket:(NSData *)packet;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
