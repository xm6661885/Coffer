#import <AVFoundation/AVFoundation.h>
@class VLCMediaPlayer;

NS_ASSUME_NONNULL_BEGIN

// Bridges the bundled libVLC video callbacks to the system's sample-buffer renderer.
@interface VLCVideoOutput : NSObject
@property (nonatomic, readonly) AVSampleBufferDisplayLayer *displayLayer;
@property (nonatomic, readonly) NSUInteger frameCount;
@property (nonatomic, readonly) CGSize videoSize;
- (instancetype)initWithDisplayLayer:(AVSampleBufferDisplayLayer *)layer;
- (void)attachToPlayer:(VLCMediaPlayer *)player;
- (void)invalidate;
- (void)setPlaybackTime:(double)seconds rate:(float)rate;
+ (void)retirePlayer:(VLCMediaPlayer *)player output:(nullable VLCVideoOutput *)output completion:(void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END
