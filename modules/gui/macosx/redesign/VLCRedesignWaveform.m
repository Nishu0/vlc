/*****************************************************************************
 * VLCRedesignWaveform.m: Waveform seek bar for music playback
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignWaveform.h"
#import "VLCRedesignAppearance.h"
#import "extensions/NSString+Helpers.h"
#import <AVFoundation/AVFoundation.h>

/* Figma 4767:23726: 2 pt bars every 5 pt inside a 28 pt recessed track,
 * played bars in the dimmed accent, a 4 pt playhead in the accent. */
static const CGFloat VLCWaveformBarWidth = 2;
static const CGFloat VLCWaveformBarPitch = 5;
static const CGFloat VLCWaveformInset = 2;
static const NSUInteger VLCWaveformBuckets = 1024;

/* Peak level of each bucket of a local file, from 0 to 1. Returns nil when
 * AVFoundation cannot read the format; VLC still plays it. */
static NSArray<NSNumber *> *VLCWaveformPeaks(NSURL *url, BOOL (^cancelled)(void))
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    double duration = CMTimeGetSeconds(asset.duration);
    if (!track || !(duration > 0))
        return nil;
    NSError *error = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (!reader)
        return nil;
    /* Mono 16-bit at a low rate is plenty for bar heights and keeps decoding fast */
    NSDictionary *settings = @{
        AVFormatIDKey : @(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey : @16,
        AVLinearPCMIsFloatKey : @NO,
        AVLinearPCMIsBigEndianKey : @NO,
        AVLinearPCMIsNonInterleaved : @NO,
        AVNumberOfChannelsKey : @1,
        AVSampleRateKey : @8000
    };
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                  outputSettings:settings];
    if (![reader canAddOutput:output])
        return nil;
    [reader addOutput:output];
    if (![reader startReading])
        return nil;
    double totalSamples = duration * 8000;
    float *peaks = calloc(VLCWaveformBuckets, sizeof(float));
    if (!peaks)
        return nil;
    uint64_t sampleIndex = 0;
    CMSampleBufferRef buffer;
    while ((buffer = [output copyNextSampleBuffer])) {
        if (cancelled()) {
            CFRelease(buffer);
            [reader cancelReading];
            free(peaks);
            return nil;
        }
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(buffer);
        size_t length = 0;
        char *data = NULL;
        if (block && CMBlockBufferGetDataPointer(block, 0, NULL, &length, &data) == kCMBlockBufferNoErr) {
            const int16_t *samples = (const int16_t *)data;
            for (size_t i = 0; i < length / sizeof(int16_t); i++, sampleIndex++) {
                NSUInteger bucket = MIN(VLCWaveformBuckets - 1, (NSUInteger)(sampleIndex / totalSamples * VLCWaveformBuckets));
                float level = fabsf(samples[i] / 32768.f);
                if (level > peaks[bucket])
                    peaks[bucket] = level;
            }
        }
        CFRelease(buffer);
    }
    BOOL completed = reader.status == AVAssetReaderStatusCompleted;
    float loudest = 0;
    for (NSUInteger i = 0; i < VLCWaveformBuckets; i++)
        loudest = MAX(loudest, peaks[i]);
    NSMutableArray *result = nil;
    if (completed && loudest > 0) {
        result = [NSMutableArray arrayWithCapacity:VLCWaveformBuckets];
        for (NSUInteger i = 0; i < VLCWaveformBuckets; i++)
            [result addObject:@(peaks[i] / loudest)];
    }
    free(peaks);
    return result;
}

@interface VLCRedesignWaveform ()
@property (nullable) NSArray<NSNumber *> *peaks;
@property (nullable) NSURL *loadedURL;
@property (atomic) NSUInteger generation;
@property (readwrite) BOOL dragging;
@end

@implementation VLCRedesignWaveform

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _enabled = YES;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilitySliderRole;
        self.accessibilityLabel = _NS("Playback position");
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(redraw)
                                                   name:VLCRedesignAppearanceChanged
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)redraw
{
    self.needsDisplay = YES;
}

- (void)setPosition:(double)position
{
    if (_dragging)
        return;
    _position = MAX(0, MIN(1, position));
    self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    self.needsDisplay = YES;
}

- (id)accessibilityValue
{
    return @(_position);
}

- (void)loadURL:(NSURL *)url
{
    if ([url isEqual:_loadedURL])
        return;
    _loadedURL = url;
    _peaks = nil;
    self.needsDisplay = YES;
    NSUInteger generation = ++self.generation;
    if (!url.isFileURL)
        return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *peaks = VLCWaveformPeaks(url, ^BOOL {
            return weakSelf == nil || weakSelf.generation != generation;
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) waveform = weakSelf;
            if (!waveform || waveform.generation != generation)
                return;
            waveform.peaks = peaks;
            waveform.needsDisplay = YES;
        });
    });
}

- (CGFloat)levelForBar:(NSUInteger)bar of:(NSUInteger)count
{
    if (!_peaks.count)
        return .25;
    NSUInteger start = bar * _peaks.count / count, end = MAX(start + 1, (bar + 1) * _peaks.count / count);
    double level = 0;
    for (NSUInteger i = start; i < end && i < _peaks.count; i++)
        level = MAX(level, _peaks[i].doubleValue);
    return level;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    [VLCRedesignAppearance.recessedColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:6 yRadius:6] fill];
    CGFloat inner = NSWidth(bounds) - 2 * VLCWaveformInset;
    if (inner <= 0)
        return;
    NSUInteger count = (NSUInteger)floor((inner + VLCWaveformBarPitch - VLCWaveformBarWidth) / VLCWaveformBarPitch);
    CGFloat playhead = VLCWaveformInset + inner * _position;
    CGFloat maxHeight = NSHeight(bounds) - 14, midY = NSMidY(bounds);
    NSColor *played = [VLCRedesignAppearance.accentColor blendedColorWithFraction:.2
                                                                          ofColor:NSColor.blackColor];
    NSColor *unplayed = VLCRedesignAppearance.dark ? [VLCRedesignAppearance colorWithRGB:0x404040]
                                                   : [VLCRedesignAppearance colorWithRGB:0xb0b0b0];
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat x = VLCWaveformInset + 3 + i * VLCWaveformBarPitch;
        if (x + VLCWaveformBarWidth > NSMaxX(bounds) - VLCWaveformInset)
            break;
        CGFloat height = MAX(2, round(maxHeight * [self levelForBar:i of:count]));
        [(x < playhead && _enabled ? played : unplayed) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, round(midY - height / 2), VLCWaveformBarWidth, height)
                                         xRadius:1
                                         yRadius:1] fill];
    }
    if (!_enabled)
        return;
    [VLCRedesignAppearance.accentColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(MAX(VLCWaveformInset, playhead - 2), VLCWaveformInset, 4,
                                                        NSHeight(bounds) - 2 * VLCWaveformInset)
                                     xRadius:2
                                     yRadius:2] fill];
}

#pragma mark - Seeking

- (double)positionForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    return MAX(0, MIN(1, (point.x - VLCWaveformInset) / MAX(1, NSWidth(self.bounds) - 2 * VLCWaveformInset)));
}

- (void)seekWithEvent:(NSEvent *)event finished:(BOOL)finished
{
    _position = [self positionForEvent:event];
    self.needsDisplay = YES;
    if (self.seek)
        self.seek(_position, finished);
}

- (void)mouseDown:(NSEvent *)event
{
    if (!_enabled)
        return;
    self.dragging = YES;
    [self seekWithEvent:event finished:NO];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_dragging)
        [self seekWithEvent:event finished:NO];
}

- (void)mouseUp:(NSEvent *)event
{
    if (!_dragging)
        return;
    [self seekWithEvent:event finished:YES];
    self.dragging = NO;
}

@end
