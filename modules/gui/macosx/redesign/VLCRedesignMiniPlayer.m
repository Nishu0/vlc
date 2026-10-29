/*****************************************************************************
 * VLCRedesignMiniPlayer.m: Floating player shown while browsing the library
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignMiniPlayer.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignIconButton.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"
#import "library/VLCInputItem.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

const NSSize VLCRedesignMiniPlayerSize = {391, 339};

static NSString *const VLCMiniPlayerCornerKey = @"VLCRedesignMiniPlayerLeftCorner";
static const CGFloat VLCMiniPlayerPadding = 8;
static const CGFloat VLCMiniPlayerProgressHeight = 16;

/* Thick seek track: a recessed 16 pt bar with a 12 pt fill inset by 2 pt. */
@interface VLCMiniPlayerProgress : NSView
@property (nonatomic) CGFloat position;
@property (copy) void (^seek)(CGFloat position);
@end
@implementation VLCMiniPlayerProgress

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (void)setPosition:(CGFloat)position
{
    _position = MAX(0, MIN(1, position));
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [VLCRedesignAppearance.recessedColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    CGFloat width = floor((NSWidth(self.bounds) - 4) * _position);
    if (width < 1)
        return;
    [VLCRedesignAppearance.accentBackingColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 2, width, NSHeight(self.bounds) - 4) xRadius:4 yRadius:4]
        fill];
}

- (void)seekToEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat position = MAX(0, MIN(1, (point.x - 2) / MAX(1, NSWidth(self.bounds) - 4)));
    self.position = position;
    if (self.seek)
        self.seek(position);
}

- (void)mouseDown:(NSEvent *)event
{
    [self seekToEvent:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    [self seekToEvent:event];
}

@end

/* Video or artwork slot; mouse events fall through to the card so it can be
 * dragged or clicked to return to the player. */
@interface VLCMiniPlayerScreen : NSView
@property NSImageView *artwork;
@end
@implementation VLCMiniPlayerScreen

- (BOOL)isFlipped
{
    return YES;
}

- (NSView *)hitTest:(NSPoint)point
{
    return NSPointInRect([self.superview convertPoint:point toView:self], self.bounds) ? self : nil;
}

- (void)mouseDown:(NSEvent *)event
{
    [self.superview mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    [self.superview mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event
{
    [self.superview mouseUp:event];
}

@end

@interface VLCRedesignMiniPlayer ()
@property VLCMiniPlayerScreen *screen;
@property (nullable) NSView *videoView;
@property VLCMiniPlayerProgress *progress;
@property VLCRedesignAlignedLabel *title;
@property NSImageView *folderIcon;
@property VLCRedesignAlignedLabel *folder;
@property VLCPlayerIconButton *queueButton;
@property NSPoint dragOrigin;
@property NSPoint dragStartOrigin;
@property BOOL dragged;
@end

@implementation VLCRedesignMiniPlayer

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (VLCPlayerController *)player
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 14;
    self.layer.shadowColor = [NSColor colorWithWhite:0 alpha:.38].CGColor;
    self.layer.shadowOpacity = 1;
    self.layer.shadowRadius = 6;
    self.layer.shadowOffset = CGSizeZero;
    _leftCorner = [NSUserDefaults.standardUserDefaults boolForKey:VLCMiniPlayerCornerKey];

    _screen = [[VLCMiniPlayerScreen alloc] init];
    _screen.wantsLayer = YES;
    _screen.layer.cornerRadius = 6;
    _screen.layer.borderWidth = 2;
    _screen.layer.masksToBounds = YES;
    _screen.artwork = [[NSImageView alloc] init];
    _screen.artwork.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_screen addSubview:_screen.artwork];
    [self addSubview:_screen];

    __weak typeof(self) weakSelf = self;
    _progress = [[VLCMiniPlayerProgress alloc] init];
    _progress.seek = ^(CGFloat position) {
        [weakSelf.player setPositionPrecise:position];
    };
    _progress.toolTip = _progress.accessibilityLabel = _NS("Playback position");
    [self addSubview:_progress];

    _title = [VLCRedesignAlignedLabel labelWithString:@""];
    _title.font = [VLCRedesignAppearance fontOfSize:16 weight:NSFontWeightRegular];
    _title.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self addSubview:_title];
    _folderIcon = [[NSImageView alloc] init];
    [self addSubview:_folderIcon];
    _folder = [VLCRedesignAlignedLabel labelWithString:@""];
    _folder.font = [VLCRedesignAppearance fontOfSize:16 weight:NSFontWeightRegular];
    _folder.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_folder];
    _queueButton = [[VLCPlayerIconButton alloc] init];
    _queueButton.assetRole = @"queue";
    _queueButton.title = @"";
    _queueButton.bordered = NO;
    _queueButton.target = self;
    _queueButton.action = @selector(showQueue:);
    _queueButton.toolTip = _queueButton.accessibilityLabel = _NS("Play Queue");
    [self addSubview:_queueButton];

    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityGroupRole;
    self.accessibilityLabel = _NS("Mini player");

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[ VLCPlayerCurrentMediaItemChanged, VLCPlayerMetadataChangedForCurrentMedia ])
        [center addObserver:self selector:@selector(updateMedia) name:name object:nil];
    [center addObserver:self selector:@selector(updatePosition) name:VLCPlayerTimeAndPositionChanged object:nil];
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
    _screen.layer.backgroundColor = VLCRedesignAppearance.hoverColor.CGColor;
    _screen.layer.borderColor = VLCRedesignAppearance.recessedColor.CGColor;
    _title.textColor = _folder.textColor = VLCRedesignAppearance.subduedColor;
    _folderIcon.image = VLCPlayerAsset(@"folder");
    _queueButton.image = VLCPlayerAsset(@"queue");
    [VLCRedesignAppearance redisplay:self];
}

- (void)updateMedia
{
    VLCInputItem *media = self.player.currentMedia;
    _title.stringValue = media.name ?: @"";
    _title.toolTip = media.name;
    NSURL *url = self.player.URLOfCurrentMediaItem;
    _folder.stringValue = url.isFileURL ? url.URLByDeletingLastPathComponent.lastPathComponent : @"";
    _folder.toolTip = url.isFileURL ? url.URLByDeletingLastPathComponent.path : nil;
    _folder.hidden = _folderIcon.hidden = !url.isFileURL;
    NSURL *artwork = media.artworkURL;
    _screen.artwork.image = artwork ? [[NSImage alloc] initWithContentsOfURL:artwork] : nil;
    [self updatePosition];
}

- (void)updatePosition
{
    _progress.position = self.player.position;
}

- (void)setVideoView:(NSView *)videoView
{
    if (_videoView == videoView)
        return;
    if (_videoView.superview == _screen)
        [_videoView removeFromSuperview];
    _videoView = videoView;
    _screen.artwork.hidden = videoView != nil;
    if (videoView) {
        /* The player lays the video out by frame too; constraints would fight its autoresizing */
        videoView.translatesAutoresizingMaskIntoConstraints = YES;
        videoView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        videoView.frame = _screen.bounds;
        [_screen addSubview:videoView];
    }
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds) - 2 * VLCMiniPlayerPadding;
    CGFloat videoHeight = floor(width * 9. / 16.);
    _screen.frame = NSMakeRect(VLCMiniPlayerPadding, VLCMiniPlayerPadding, width, videoHeight);
    _screen.artwork.frame = _screen.bounds;
    _videoView.frame = _screen.bounds;
    _progress.frame = NSMakeRect(VLCMiniPlayerPadding, NSMaxY(_screen.frame) + 4, width, VLCMiniPlayerProgressHeight);
    /* Text block: 20 pt below the progress, 8 pt side and 4 pt top padding, 14 pt between rows */
    CGFloat textX = VLCMiniPlayerPadding * 2, textWidth = width - VLCMiniPlayerPadding * 2;
    CGFloat y = NSMaxY(_progress.frame) + 20 + 4;
    _title.frame = NSMakeRect(textX, y, textWidth, 20);
    y += 20 + 14;
    _queueButton.frame = NSMakeRect(textX + textWidth - 30, y, 30, 32);
    _folderIcon.frame = NSMakeRect(textX, y + 4, 24, 24);
    _folder.frame = NSMakeRect(textX + 32, y + 4, MAX(0, NSMinX(_queueButton.frame) - textX - 40), 24);
}

#pragma mark - Interaction

- (void)showQueue:(id)sender
{
    if (self.openQueue)
        self.openQueue();
}

- (void)mouseDown:(NSEvent *)event
{
    _dragOrigin = [self.superview convertPoint:event.locationInWindow fromView:nil];
    _dragStartOrigin = self.frame.origin;
    _dragged = NO;
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint point = [self.superview convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - _dragOrigin.x, dy = point.y - _dragOrigin.y;
    if (!_dragged && hypot(dx, dy) < 4)
        return;
    _dragged = YES;
    [self setFrameOrigin:NSMakePoint(_dragStartOrigin.x + dx, _dragStartOrigin.y + dy)];
}

- (void)mouseUp:(NSEvent *)event
{
    if (!_dragged) {
        if (self.openPlayer)
            self.openPlayer();
        return;
    }
    /* Settle into whichever lower corner is nearer, as in Figma 970:3308 and 970:3792 */
    _leftCorner = NSMidX(self.frame) < NSMidX(self.superview.bounds);
    [NSUserDefaults.standardUserDefaults setBool:_leftCorner forKey:VLCMiniPlayerCornerKey];
    if (self.cornerChanged)
        self.cornerChanged();
}

@end
