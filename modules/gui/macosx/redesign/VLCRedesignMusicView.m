/*****************************************************************************
 * VLCRedesignMusicView.m: Artwork presentation for audio playback
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignMusicView.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryImageCache.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import <CoreImage/CoreImage.h>

/* Reference geometry at 1920 × 1080: 738 pt artwork with 20 pt corners,
 * caption 24 pt Inter Medium below it. */
static const CGFloat VLCMusicArtworkMaximum = 738;
static const CGFloat VLCMusicArtworkRadius = 20;
static const CGFloat VLCMusicCaptionGap = 40;
static const CGFloat VLCMusicCaptionHeight = 30;

static NSImage *VLCMusicBlurred(NSImage *image)
{
    CGImageRef source = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!source)
        return nil;
    CIImage *input = [CIImage imageWithCGImage:source];
    /* 10 pt of blur on the 1952 pt reference backdrop, relative to the source size */
    CGFloat radius = MAX(2, CGImageGetWidth(source) * 10. / 1952. * 2);
    CIImage *blurred = [[input imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:radius];
    blurred = [blurred imageByCroppingToRect:input.extent];
    NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage:blurred];
    NSImage *result = [[NSImage alloc] initWithSize:rep.size];
    [result addRepresentation:rep];
    return result;
}

/* Square artwork, centred and cropped to fill. */
@interface VLCMusicArtworkView : NSView
@property (nullable) NSImage *image;
@property CGFloat radius;
@end
@implementation VLCMusicArtworkView

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:_radius yRadius:_radius] addClip];
    NSSize size = _image.size;
    if (size.width > 0 && size.height > 0) {
        CGFloat scale = MAX(NSWidth(bounds) / size.width, NSHeight(bounds) / size.height);
        NSRect rect = NSMakeRect(NSMidX(bounds) - size.width * scale / 2, NSMidY(bounds) - size.height * scale / 2,
                                 size.width * scale, size.height * scale);
        [_image drawInRect:rect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1
            respectFlipped:YES
                     hints:nil];
    } else {
        [VLCRedesignAppearance.recessedColor setFill];
        NSRectFill(bounds);
    }
    [NSGraphicsContext restoreGraphicsState];
}

@end

@interface VLCRedesignMusicView ()
@property VLCMusicArtworkView *backdrop;
// Keeps the caption readable over bright artwork; dark artwork, as in the design, barely changes
@property NSView *scrim;
@property VLCMusicArtworkView *artwork;
@property NSView *glow;
@property VLCRedesignAlignedLabel *caption;
@property (nullable) NSString *artworkKey;
@end

@implementation VLCRedesignMusicView

- (BOOL)isFlipped
{
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    _backdrop = [[VLCMusicArtworkView alloc] init];
    [self addSubview:_backdrop];
    _scrim = [[NSView alloc] init];
    _scrim.wantsLayer = YES;
    [self addSubview:_scrim];
    /* Soft white halo behind the artwork: 0 0 90 64 rgba(255,255,255,.03) in the design */
    _glow = [[NSView alloc] init];
    _glow.wantsLayer = YES;
    _glow.layer.cornerRadius = VLCMusicArtworkRadius;
    _glow.layer.shadowColor = NSColor.whiteColor.CGColor;
    _glow.layer.shadowOpacity = .06;
    _glow.layer.shadowRadius = 60;
    _glow.layer.shadowOffset = CGSizeZero;
    [self addSubview:_glow];
    _artwork = [[VLCMusicArtworkView alloc] init];
    _artwork.radius = VLCMusicArtworkRadius;
    [self addSubview:_artwork];
    _caption = [VLCRedesignAlignedLabel labelWithString:@""];
    _caption.font = [VLCRedesignAppearance fontOfSize:24 weight:NSFontWeightMedium];
    _caption.alignment = NSTextAlignmentCenter;
    _caption.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_caption];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[ VLCPlayerCurrentMediaItemChanged, VLCPlayerMetadataChangedForCurrentMedia ])
        [center addObserver:self selector:@selector(updateMedia) name:name object:nil];
    [center addObserver:self selector:@selector(updateAppearance) name:VLCRedesignAppearanceChanged object:nil];
    [self updateAppearance];
    [self updateMedia];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)updateAppearance
{
    self.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    _glow.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    _scrim.layer.backgroundColor = [VLCRedesignAppearance.panelColor colorWithAlphaComponent:.6].CGColor;
    _caption.textColor = VLCRedesignAppearance.subduedColor;
    [VLCRedesignAppearance redisplay:self];
}

- (void)updateMedia
{
    VLCInputItem *media = VLCMain.sharedInstance.playQueueController.playerController.currentMedia;
    NSString *title = media.title.length ? media.title : media.name;
    _caption.stringValue = media.artist.length && title.length
                               ? [NSString stringWithFormat:@"%@ - %@", title, media.artist]
                               : title ?: @"";
    _caption.toolTip = _caption.stringValue;
    NSString *key = [NSString stringWithFormat:@"%@|%@", media.MRL ?: @"", media.artworkURL.absoluteString ?: @""];
    if ([key isEqualToString:_artworkKey])
        return;
    _artworkKey = key;
    if (!media) {
        _artwork.image = _backdrop.image = nil;
        [VLCRedesignAppearance redisplay:self];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [VLCLibraryImageCache thumbnailForInputItem:media
                                 withCompletion:^(const NSImage *image) {
                                     typeof(self) view = weakSelf;
                                     if (!view || ![view.artworkKey isEqualToString:key])
                                         return;
                                     view.artwork.image = (NSImage *)image;
                                     view.backdrop.image = image ? VLCMusicBlurred((NSImage *)image) : nil;
                                     view.artwork.needsDisplay = view.backdrop.needsDisplay = YES;
                                 }];
}

- (void)layout
{
    [super layout];
    NSRect bounds = self.bounds;
    /* The backdrop overfills the view like the 1952 pt square behind a 1920 pt frame */
    CGFloat backdrop = MAX(NSWidth(bounds), NSHeight(bounds)) * 1.02;
    _backdrop.frame = NSMakeRect(NSMidX(bounds) - backdrop / 2, NSMidY(bounds) - backdrop / 2, backdrop, backdrop);
    _scrim.frame = bounds;
    CGFloat available = NSHeight(bounds) - VLCMusicCaptionGap - VLCMusicCaptionHeight - 80;
    CGFloat side = floor(MAX(80, MIN(VLCMusicArtworkMaximum, MIN(available, NSWidth(bounds) - 80))));
    CGFloat blockHeight = side + VLCMusicCaptionGap + VLCMusicCaptionHeight;
    CGFloat top = floor(MAX(20, (NSHeight(bounds) - blockHeight) / 2));
    _artwork.frame = NSMakeRect(floor(NSMidX(bounds) - side / 2), top, side, side);
    _glow.frame = _artwork.frame;
    _artwork.radius = side < 300 ? 12 : VLCMusicArtworkRadius;
    _glow.layer.cornerRadius = _artwork.radius;
    _caption.frame = NSMakeRect(20, NSMaxY(_artwork.frame) + VLCMusicCaptionGap, MAX(0, NSWidth(bounds) - 40),
                                VLCMusicCaptionHeight);
    _caption.font = [VLCRedesignAppearance fontOfSize:side < 300 ? 18 : 24 weight:NSFontWeightMedium];
    _caption.hidden = NSHeight(bounds) < 240;
}

@end
