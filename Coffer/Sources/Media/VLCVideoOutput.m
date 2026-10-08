#import "VLCVideoOutput.h"
#import <MobileVLCKit/VLCMediaPlayer.h>
#import <os/lock.h>

// These functions and this getter are exported by the bundled VLCKit 3 library.
// Keep the declarations limited to the public libVLC callback ABI we actually use.
typedef struct libvlc_media_player_t libvlc_media_player_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct {
    uint32_t codec; int id, type, profile, level;
    union { struct { unsigned channels, rate; } audio; struct { unsigned height, width; } video; } details;
} CofferVLCTrackInfo;
@interface VLCMediaPlayer (CofferVideoInstance)
@property (nonatomic, readonly) libvlc_media_player_t *playerInstance;
@end
extern void libvlc_video_set_callbacks(libvlc_media_player_t *, void *(*)(void *, void **), void (*)(void *, void *, void *const *), void (*)(void *, void *), void *);
extern void libvlc_video_set_format_callbacks(libvlc_media_player_t *, unsigned (*)(void **, char *, unsigned *, unsigned *, unsigned *, unsigned *), void (*)(void *));
extern void libvlc_media_player_stop(libvlc_media_player_t *);
extern libvlc_media_t *libvlc_media_player_get_media(libvlc_media_player_t *);
extern int libvlc_media_get_tracks_info(libvlc_media_t *, CofferVLCTrackInfo **);
extern void libvlc_media_release(libvlc_media_t *);
extern int libvlc_video_get_track(libvlc_media_player_t *);

typedef struct {
    CVPixelBufferRef buffer;
    CMVideoFormatDescriptionRef format;
    NSUInteger generation;
    BOOL emergency;
} CofferVideoPicture;

@interface VLCVideoOutput () {
    os_unfair_lock _lock;
    CVPixelBufferPoolRef _pool;
    CMVideoFormatDescriptionRef _format;
    NSUInteger _generation;
    NSUInteger _frameCount;
    CGSize _videoSize;
    BOOL _invalidated;
    BOOL _scheduled;
    CVPixelBufferRef _pendingBuffer;
    CMVideoFormatDescriptionRef _pendingFormat;
    NSUInteger _pendingGeneration;
    dispatch_queue_t _renderQueue;
    libvlc_media_player_t *_instance;
    CVPixelBufferRef _emergencyBuffer;
    CofferVideoPicture _emergencyPicture;
}
- (unsigned)configureChroma:(char *)chroma width:(unsigned *)width height:(unsigned *)height pitches:(unsigned *)pitches lines:(unsigned *)lines;
- (void *)lockPlanes:(void **)planes;
- (void)displayPicture:(CofferVideoPicture *)picture;
- (void)cleanupFormat;
- (void)renderPending;
@end

static unsigned CofferVideoSetup(void **opaque, char *chroma, unsigned *width, unsigned *height, unsigned *pitches, unsigned *lines) {
    @autoreleasepool { return [(__bridge VLCVideoOutput *)*opaque configureChroma:chroma width:width height:height pitches:pitches lines:lines]; }
}
static void CofferVideoCleanup(void *opaque) { @autoreleasepool { [(__bridge VLCVideoOutput *)opaque cleanupFormat]; } }
static void *CofferVideoLock(void *opaque, void **planes) { @autoreleasepool { return [(__bridge VLCVideoOutput *)opaque lockPlanes:planes]; } }
static void CofferVideoUnlock(void *opaque, void *picture, void *const *planes) {
    CofferVideoPicture *frame = picture;
    if (frame) CVPixelBufferUnlockBaseAddress(frame->buffer, 0);
}
static void CofferVideoDisplay(void *opaque, void *picture) {
    @autoreleasepool { [(__bridge VLCVideoOutput *)opaque displayPicture:picture]; }
}

@implementation VLCVideoOutput
- (instancetype)initWithDisplayLayer:(AVSampleBufferDisplayLayer *)layer {
    if ((self = [super init])) {
        _displayLayer = layer; _lock = OS_UNFAIR_LOCK_INIT;
        _renderQueue = dispatch_queue_create("app.coffer.vlc.video", DISPATCH_QUEUE_SERIAL);
        CMTimebaseRef timebase = NULL;
        if (CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase) == noErr) {
            layer.controlTimebase = timebase; CFRelease(timebase);
        }
    }
    return self;
}
- (void)attachToPlayer:(VLCMediaPlayer *)player {
    _instance = player.playerInstance;
    libvlc_video_set_callbacks(player.playerInstance, CofferVideoLock, CofferVideoUnlock, CofferVideoDisplay, (__bridge void *)self);
    libvlc_video_set_format_callbacks(player.playerInstance, CofferVideoSetup, CofferVideoCleanup);
}
+ (void)retirePlayer:(VLCMediaPlayer *)player output:(VLCVideoOutput *)output completion:(void (^)(void))completion {
    [output invalidate];
    // stop() in VLCKit is asynchronous. Keep the player and callback owner alive
    // until the synchronous libVLC stop has joined its decoder/output threads.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        libvlc_media_player_stop(player.playerInstance);
        if (output) {
            libvlc_video_set_callbacks(player.playerInstance, NULL, NULL, NULL, NULL);
            libvlc_video_set_format_callbacks(player.playerInstance, NULL, NULL);
        }
        dispatch_async(dispatch_get_main_queue(), completion);
    });
}
- (NSUInteger)frameCount { os_unfair_lock_lock(&_lock); NSUInteger value = _frameCount; os_unfair_lock_unlock(&_lock); return value; }
- (CGSize)videoSize { os_unfair_lock_lock(&_lock); CGSize value = _videoSize; os_unfair_lock_unlock(&_lock); return value; }
- (void)setPlaybackTime:(double)seconds rate:(float)rate {
    CMTimebaseRef timebase = _displayLayer.controlTimebase;
    if (timebase) { CMTimebaseSetTime(timebase, CMTimeMakeWithSeconds(MAX(0, seconds), 600)); CMTimebaseSetRate(timebase, rate); }
}
- (unsigned)configureChroma:(char *)chroma width:(unsigned *)width height:(unsigned *)height pitches:(unsigned *)pitches lines:(unsigned *)lines {
    if (*width == 0 || *height == 0 || *width > 16384 || *height > 16384) return 0;
    // vmem receives coded dimensions, including codec padding. Request the
    // visible track dimensions to avoid changing the image's aspect ratio.
    libvlc_media_t *media = _instance ? libvlc_media_player_get_media(_instance) : NULL;
    if (media) {
        CofferVLCTrackInfo *tracks = NULL;
        int count = libvlc_media_get_tracks_info(media, &tracks), selected = libvlc_video_get_track(_instance);
        for (int i = 0; i < count; i++) {
            if (tracks[i].type != 1 || (selected >= 0 && tracks[i].id != selected)) continue;
            unsigned w = tracks[i].details.video.width, h = tracks[i].details.video.height;
            if (w > 0 && h > 0 && w <= 16384 && h <= 16384) {
                if ((w > h && *width < *height) || (w < h && *width > *height)) { unsigned swap = w; w = h; h = swap; }
                *width = w; *height = h;
            }
            break;
        }
        free(tracks); libvlc_media_release(media);
    }
    unsigned w = (*width + 1) & ~1U, h = (*height + 1) & ~1U;
    NSDictionary *attributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h),
        (id)kCVPixelBufferBytesPerRowAlignmentKey: @64,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVPixelBufferPoolRef pool = NULL;
    if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &pool) != kCVReturnSuccess) return 0;
    CVPixelBufferRef buffer = NULL;
    CMVideoFormatDescriptionRef format = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) != kCVReturnSuccess) { CFRelease(pool); return 0; }
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, h >= 720 ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, buffer, &format) != noErr) { CFRelease(buffer); CFRelease(pool); return 0; }
    memcpy(chroma, "NV12", 4); *width = w; *height = h;
    for (size_t plane = 0; plane < 2; plane++) { pitches[plane] = (unsigned)CVPixelBufferGetBytesPerRowOfPlane(buffer, plane); lines[plane] = (unsigned)CVPixelBufferGetHeightOfPlane(buffer, plane); }
    os_unfair_lock_lock(&_lock);
    if (_pool) CFRelease(_pool); if (_format) CFRelease(_format);
    if (_emergencyBuffer) CFRelease(_emergencyBuffer);
    _emergencyBuffer = buffer;
    _pool = pool; _format = format; _videoSize = CGSizeMake(w, h); _generation++;
    os_unfair_lock_unlock(&_lock);
    return 3;
}
- (void *)lockPlanes:(void **)planes {
    os_unfair_lock_lock(&_lock);
    CVPixelBufferPoolRef pool = _pool ? (CVPixelBufferPoolRef)CFRetain(_pool) : NULL;
    CMVideoFormatDescriptionRef format = _format ? (CMVideoFormatDescriptionRef)CFRetain(_format) : NULL;
    NSUInteger generation = _generation;
    os_unfair_lock_unlock(&_lock);
    if (!pool || !format) { if (pool) CFRelease(pool); if (format) CFRelease(format); return NULL; }
    CVPixelBufferRef buffer = NULL;
    NSDictionary *limit = @{ (id)kCVPixelBufferPoolAllocationThresholdKey: @8 };
    CVReturn result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, (__bridge CFDictionaryRef)limit, &buffer);
    CFRelease(pool);
    CofferVideoPicture *picture = result == kCVReturnSuccess ? calloc(1, sizeof(*picture)) : NULL;
    if (!picture) {
        if (buffer) CFRelease(buffer); CFRelease(format);
        // libVLC's lock ABI requires writable planes even when a frame is
        // dropped. The preallocated emergency buffer bounds memory at nine
        // pixel buffers and remains independent of the renderer's buffers.
        picture = &_emergencyPicture; picture->emergency = YES;
        picture->buffer = _emergencyBuffer; picture->format = NULL;
        CVPixelBufferLockBaseAddress(picture->buffer, 0);
        planes[0] = CVPixelBufferGetBaseAddressOfPlane(picture->buffer, 0); planes[1] = CVPixelBufferGetBaseAddressOfPlane(picture->buffer, 1);
        return picture;
    }
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, CVPixelBufferGetHeight(buffer) >= 720 ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    picture->buffer = buffer; picture->format = format; picture->generation = generation;
    CVPixelBufferLockBaseAddress(buffer, 0);
    planes[0] = CVPixelBufferGetBaseAddressOfPlane(buffer, 0); planes[1] = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
    return picture;
}
- (void)displayPicture:(CofferVideoPicture *)picture {
    if (!picture) return;
    if (picture->emergency) return;
    os_unfair_lock_lock(&_lock);
    if (!_invalidated && picture->generation == _generation) {
        if (_pendingBuffer) CFRelease(_pendingBuffer); if (_pendingFormat) CFRelease(_pendingFormat);
        _pendingBuffer = picture->buffer; _pendingFormat = picture->format; _pendingGeneration = picture->generation;
        picture->buffer = NULL; picture->format = NULL;
        if (!_scheduled) { _scheduled = YES; dispatch_async(_renderQueue, ^{ [self renderPending]; }); }
    }
    os_unfair_lock_unlock(&_lock);
    if (picture->buffer) CFRelease(picture->buffer); if (picture->format) CFRelease(picture->format); free(picture);
}
- (void)renderPending {
    os_unfair_lock_lock(&_lock);
    CVPixelBufferRef buffer = _pendingBuffer; CMVideoFormatDescriptionRef format = _pendingFormat;
    NSUInteger generation = _pendingGeneration;
    _pendingBuffer = NULL; _pendingFormat = NULL; _scheduled = NO;
    BOOL valid = !_invalidated && generation == _generation;
    os_unfair_lock_unlock(&_lock);
    if (valid && buffer && format) {
        AVSampleBufferVideoRenderer *renderer = _displayLayer.sampleBufferRenderer;
        if (renderer.requiresFlushToResumeDecoding || renderer.status == AVQueuedSampleBufferRenderingStatusFailed) [renderer flush];
        if (renderer.readyForMoreMediaData) {
            CMSampleTimingInfo timing = { kCMTimeInvalid, CMTimebaseGetTime(_displayLayer.controlTimebase), kCMTimeInvalid };
            CMSampleBufferRef sample = NULL;
            if (CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, buffer, format, &timing, &sample) == noErr) {
                CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, YES);
                if (attachments && CFArrayGetCount(attachments)) CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0), kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
                // Invalidation and enqueue share a lock so an old decoder cannot
                // deliver a frame after another item takes over the shared layer.
                os_unfair_lock_lock(&_lock);
                if (!_invalidated && generation == _generation) { [renderer enqueueSampleBuffer:sample]; _frameCount++; }
                os_unfair_lock_unlock(&_lock);
                CFRelease(sample);
            }
        }
    }
    if (buffer) CFRelease(buffer); if (format) CFRelease(format);
}
- (void)cleanupFormat {
    os_unfair_lock_lock(&_lock);
    if (_pool) { CFRelease(_pool); _pool = NULL; } if (_format) { CFRelease(_format); _format = NULL; }
    _generation++;
    os_unfair_lock_unlock(&_lock);
}
- (void)invalidate {
    os_unfair_lock_lock(&_lock); _invalidated = YES; _generation++;
    if (_pendingBuffer) { CFRelease(_pendingBuffer); _pendingBuffer = NULL; }
    if (_pendingFormat) { CFRelease(_pendingFormat); _pendingFormat = NULL; }
    os_unfair_lock_unlock(&_lock);
}
- (void)dealloc {
    if (_pool) CFRelease(_pool); if (_format) CFRelease(_format);
    if (_emergencyBuffer) CFRelease(_emergencyBuffer);
    if (_pendingBuffer) CFRelease(_pendingBuffer); if (_pendingFormat) CFRelease(_pendingFormat);
}
@end
