/*****************************************************************************
 * VLCRedesignSeekPreview.m: Independent seek thumbnails for the native player
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignSeekPreview.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "library/VLCInputItem.h"
#import "main/VLCMain.h"
#import "extensions/NSString+Helpers.h"
#include <vlc_preparser.h>

@interface VLCSeekPreviewRequest : NSObject
@property (weak) VLCRedesignSeekPreview *owner;
@property NSNumber *second;
@property NSString *path;
@property vlc_preparser_req *handle;
@end
@implementation VLCSeekPreviewRequest
@end

@interface VLCRedesignSeekPreview ()
@property VLCInputItem *inputItem;
@property NSNumber *second;
@property NSImageView *imageView;
@property VLCRedesignAlignedLabel *timeLabel;
@property VLCRedesignAlignedLabel *statusLabel;
@property NSCache<NSNumber *, NSImage *> *cache;
@property NSTimer *debounceTimer;
@property VLCSeekPreviewRequest *request;
- (void)loadPreview;
- (void)cancelRequest;
- (void)completeRequest:(VLCSeekPreviewRequest *)request image:(NSImage *)image;
@end

static void SeekPreviewEnded(vlc_preparser_req *handle, int status,
                             const bool *results, size_t count, void *opaque)
{
    @autoreleasepool {
        VLCSeekPreviewRequest *request = (__bridge_transfer VLCSeekPreviewRequest *)opaque;
        NSData *data = status == VLC_SUCCESS && count == 1 && results && results[0]
            ? [NSData dataWithContentsOfFile:request.path] : nil;
        NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
        [NSFileManager.defaultManager removeItemAtPath:request.path error:NULL];
        /* Keep the caller's handle until this main-queue completion. Cancel
         * may run while the callback is encoding/reading its result. */
        dispatch_async(dispatch_get_main_queue(), ^{
            request.handle = NULL;
            vlc_preparser_req_Release(handle);
            [request.owner completeRequest:request image:image];
        });
    }
}

@implementation VLCRedesignSeekPreview

- (BOOL)isFlipped
{
    return YES;
}

- (void)updateAppearance
{
    self.layer.backgroundColor = VLCRedesignAppearance.raisedColor.CGColor;
    [VLCRedesignAppearance redisplay:self];
}

- (instancetype)init
{
    self = [super initWithFrame:NSMakeRect(0, 0, 200, 140)];
    if (!self)
        return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.hidden = YES;
    _cache = [[NSCache alloc] init];
    _cache.countLimit = 48;
    _cache.totalCostLimit = 8 * 1024 * 1024;
    _imageView = [[NSImageView alloc] init];
    _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_imageView];
    _timeLabel = [VLCRedesignAlignedLabel labelWithString:@""];
    _timeLabel.alignment = NSTextAlignmentCenter;
    _timeLabel.font = [VLCRedesignAppearance fontOfSize:12 weight:NSFontWeightRegular];
    _timeLabel.textColor = VLCRedesignAppearance.secondaryColor;
    [self addSubview:_timeLabel];
    _statusLabel = [VLCRedesignAlignedLabel labelWithString:@""];
    _statusLabel.alignment = NSTextAlignmentCenter;
    _statusLabel.font = [VLCRedesignAppearance fontOfSize:11 weight:NSFontWeightRegular];
    _statusLabel.textColor = _timeLabel.textColor;
    [self addSubview:_statusLabel];
    self.accessibilityElement = NO;
    [self updateAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateAppearance)
                                               name:VLCRedesignAppearanceChanged
                                             object:nil];
    return self;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

- (void)layout
{
    [super layout];
    _imageView.frame = NSMakeRect(8, 8, MAX(0, NSWidth(self.bounds) - 16), 104);
    _statusLabel.frame = _imageView.frame;
    _timeLabel.frame = NSMakeRect(8, 115, MAX(0, NSWidth(self.bounds) - 16), 20);
}

- (void)showInputItem:(VLCInputItem *)item atTime:(vlc_tick_t)time
{
    if (_inputItem.vlcInputItem != item.vlcInputItem) {
        [self cancel];
        [_cache removeAllObjects];
        _inputItem = item;
    }
    NSNumber *second = @(MAX(0, SEC_FROM_VLC_TICK(time)));
    NSInteger value = second.integerValue;
    _timeLabel.stringValue = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",
        (long)(value / 3600), (long)((value / 60) % 60), (long)(value % 60)];
    self.hidden = NO;
    if ([_second isEqualToNumber:second])
        return;
    _second = second;
    [_debounceTimer invalidate];
    [self cancelRequest];
    _imageView.image = [_cache objectForKey:second];
    _statusLabel.hidden = _imageView.image != nil;
    _statusLabel.stringValue = _NS("Loading preview…");
    if (_imageView.image)
        return;
    __weak typeof(self) weakSelf = self;
    _debounceTimer = [NSTimer timerWithTimeInterval:.18 repeats:NO block:^(NSTimer *__unused timer) {
        [weakSelf loadPreview];
    }];
    [NSRunLoop.mainRunLoop addTimer:_debounceTimer forMode:NSRunLoopCommonModes];
}

- (void)loadPreview
{
    VLCSeekPreviewRequest *request = [[VLCSeekPreviewRequest alloc] init];
    request.owner = self;
    request.second = _second;
    request.path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"vlc-seek-%@.png", NSUUID.UUID.UUIDString]];
    const struct vlc_thumbnailer_arg argument = {
        .seek.type = VLC_THUMBNAILER_SEEK_TIME,
        .seek.time = VLC_TICK_FROM_SEC(request.second.longLongValue),
        .seek.speed = VLC_THUMBNAILER_SEEK_PRECISE,
    };
    const struct vlc_thumbnailer_output output = {
        .format = VLC_THUMBNAILER_FORMAT_PNG,
        .width = 320,
        .height = 0,
        .crop = false,
        .file_path = request.path.fileSystemRepresentation,
        .creat_mode = 0600,
    };
    static const struct vlc_thumbnailer_to_files_cbs callbacks = {
        .on_ended = SeekPreviewEnded,
    };
    vlc_preparser_t *thumbnailer = getThumbnailer();
    void *opaque = (__bridge_retained void *)request;
    vlc_preparser_req *handle = thumbnailer ? vlc_preparser_req_NewThumbnailToFiles(
        thumbnailer, _inputItem.vlcInputItem, &argument, &output, 1, &callbacks, opaque) : NULL;
    if (handle) {
        request.handle = handle;
        _request = request;
        if (vlc_preparser_Submit(thumbnailer, handle) == VLC_SUCCESS)
            return;
        request.handle = NULL;
        _request = nil;
        vlc_preparser_req_Release(handle);
    }
    (void) CFBridgingRelease(opaque);
    _statusLabel.stringValue = _NS("Preview unavailable");
}

- (void)completeRequest:(VLCSeekPreviewRequest *)request image:(NSImage *)image
{
    if (request != _request)
        return;
    _request = nil;
    if (image) {
        NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * 4);
        [_cache setObject:image forKey:request.second cost:cost];
    }
    _imageView.image = image;
    _statusLabel.hidden = image != nil;
    _statusLabel.stringValue = _NS("Preview unavailable");
}

- (void)cancelRequest
{
    VLCSeekPreviewRequest *request = _request;
    _request = nil;
    vlc_preparser_t *thumbnailer = getThumbnailer();
    if (request.handle && thumbnailer)
        vlc_preparser_Cancel(thumbnailer, request.handle);
}

- (void)cancel
{
    self.hidden = YES;
    [_debounceTimer invalidate];
    _debounceTimer = nil;
    [self cancelRequest];
    _second = nil;
}

- (void)viewWillMoveToWindow:(NSWindow *)window
{
    if (!window)
        [self cancel];
    [super viewWillMoveToWindow:window];
}

- (void)dealloc
{
    [_debounceTimer invalidate];
    [self cancelRequest];
}

@end
