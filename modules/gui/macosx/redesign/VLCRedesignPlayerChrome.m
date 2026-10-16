/*****************************************************************************
 * VLCRedesignPlayerChrome.m: Native redesigned playback surface
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignPlayerChrome.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "VLCRedesignTrackPanel.h"
#import "extensions/NSString+Helpers.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowSplitViewController.h"
#import "main/VLCMain.h"
#import "menus/VLCMainMenu.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "views/VLCPlaybackProgressSlider.h"
#import "views/VLCPlaybackProgressSliderCell.h"
#import "windows/video/VLCMainVideoViewController.h"
#import "windows/video/VLCVideoWindowCommon.h"
#import "windows/video/VLCVideoOutputProvider.h"

static NSImage *VLCPlayerResource(NSString *name)
{
    static NSMutableDictionary<NSString *, NSImage *> *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ images = [NSMutableDictionary dictionary]; });
    NSImage *image = images[name];
    if (!image) {
        image = [[NSImage alloc] initWithContentsOfFile:[NSBundle.mainBundle pathForResource:name ofType:@"svg"]];
        if (image) images[name] = image;
    }
    return image;
}

static NSImage *VLCPlayerAsset(NSString *role)
{
    NSString *name = [NSString stringWithFormat:@"VLC-redesign-player-%@-%@", VLCRedesignAppearance.dark ? @"dark" : @"light", role];
    return VLCPlayerResource(name);
}

@interface VLCPlayerBar : NSView
@end
@implementation VLCPlayerBar
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

@interface VLCPlayerIconButton : NSButton
@property (copy) NSString *assetRole;
@property BOOL transport;
@property BOOL playing;
@property BOOL selected;
@end

@implementation VLCPlayerIconButton
- (BOOL)sendAction:(SEL)action to:(id)target
{
    msg_Dbg(getIntf(), "redesigned player action: %s", NSStringFromSelector(action).UTF8String);
    return [super sendAction:action to:target];
}
- (void)drawRect:(NSRect)dirtyRect
{
    if (self.transport || self.highlighted || self.selected) {
        NSColor *color = self.transport ? (self.playing ? [VLCRedesignAppearance colorWithRGB:0x6B6B6B] : VLCRedesignAppearance.accentColor) : VLCRedesignAppearance.borderColor;
        [color setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.transport ? 6 : 4 yRadius:self.transport ? 6 : 4] fill];
    }
    NSImage *image = self.image;
    if (self.playing && self.transport)
        image = VLCPlayerResource(@"VLC-redesign-player-pause");
    NSSize size = image.size;
    NSRect slot = NSMakeRect(floor(NSMidX(self.bounds) - size.width / 2), floor(NSMidY(self.bounds) - size.height / 2), size.width, size.height);
    [image drawInRect:slot fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1 : .35 respectFlipped:YES hints:nil];
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:4 yRadius:4];
        ring.lineWidth = 2;
        [ring stroke];
    }
}
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
@end

@interface VLCPlayerTimeButton : NSButton
@end
@implementation VLCPlayerTimeButton
- (void)drawRect:(NSRect)dirtyRect
{
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:self.title attributes:@{
        NSFontAttributeName:[VLCRedesignAppearance fontOfSize:15 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName:VLCRedesignAppearance.subduedColor
    }];
    VLCDrawAlignedText(text, self.bounds, self.flipped, NSTextAlignmentCenter);
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:4 yRadius:4] stroke];
    }
}
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
@end

@interface VLCPlayerSeekCell : VLCPlaybackProgressSliderCell
@end
@implementation VLCPlayerSeekCell
- (CGFloat)knobThickness { return 8; }
- (NSRect)barRectFlipped:(BOOL)flipped { return self.controlView.bounds; }
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    frame = view.bounds;
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(frame);
    [VLCRedesignAppearance.recessedColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:frame xRadius:6 yRadius:6] fill];
    CGFloat position = MAX(0, MIN(1, (self.doubleValue-self.minValue)/(self.maxValue-self.minValue)));
    CGFloat x = NSMinX(frame) + 2 + position * MAX(0, NSWidth(frame)-12);
    NSColor *fill = [VLCRedesignAppearance.accentColor blendedColorWithFraction:.75 ofColor:VLCRedesignAppearance.recessedColor];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(frame)+2, NSMinY(frame)+2, x-NSMinX(frame)+6, NSHeight(frame)-4) xRadius:4 yRadius:4] fill];
    [(self.enabled ? VLCRedesignAppearance.accentColor : VLCRedesignAppearance.subduedColor) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, NSMinY(frame)+2, 8, NSHeight(frame)-4) xRadius:4 yRadius:4] fill];
    if (view.window.firstResponder == view) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 1, 1) xRadius:6 yRadius:6] stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped { [self drawWithFrame:self.controlView.bounds inView:self.controlView]; }
- (void)drawKnob:(NSRect)rect {}
- (void)drawKnob {}
@end

@interface VLCPlayerSeekSlider : VLCPlaybackProgressSlider
@property BOOL dragging;
@property (copy) void (^didFinishSeeking)(void);
@end
@implementation VLCPlayerSeekSlider
+ (Class)cellClass { return VLCPlayerSeekCell.class; }
- (BOOL)wantsUpdateLayer { return NO; }
- (void)drawRect:(NSRect)dirtyRect { [self.cell drawWithFrame:self.bounds inView:self]; }
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 28); }
- (void)mouseDown:(NSEvent *)event
{
    self.dragging = YES;
    [super mouseDown:event];
    self.dragging = NO;
    if (self.didFinishSeeking)
        self.didFinishSeeking();
}
@end

/* Original SVG background and gradient, clipped dynamically rather than redrawn. */
@interface VLCPlayerVolumeCell : NSSliderCell
@end
@implementation VLCPlayerVolumeCell
- (CGFloat)knobThickness { return 0; }
- (NSRect)barRectFlipped:(BOOL)flipped { return self.controlView.bounds; }
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    NSImage *background = VLCPlayerResource(@"VLC-redesign-player-dark-volume-background");
    [background drawInRect:NSMakeRect(NSMinX(frame), NSMidY(frame)-background.size.height/2, background.size.width, background.size.height)];
    CGFloat value = MAX(0, MIN(2, self.doubleValue));
    CGFloat filled = value <= 1 ? value * 60 : 60 + (value-1)*26;
    NSImage *gradient = VLCPlayerResource(@"VLC-redesign-player-dark-volume-gradient");
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(NSMinX(frame)+1.5, NSMinY(frame), filled, NSHeight(frame)));
    [gradient drawInRect:NSMakeRect(NSMinX(frame)+1.5, NSMidY(frame)-gradient.size.height/2, gradient.size.width, gradient.size.height)];
    [NSGraphicsContext restoreGraphicsState];
    if (view.window.firstResponder == view) {
        [VLCRedesignAppearance.accentColor setStroke];
        [NSBezierPath strokeRect:NSInsetRect(frame, 1, 1)];
    }
}
@end

@interface VLCPlayerVolumeSlider : NSSlider
@end
@implementation VLCPlayerVolumeSlider
+ (Class)cellClass { return VLCPlayerVolumeCell.class; }
- (BOOL)wantsUpdateLayer { return NO; }
- (void)drawRect:(NSRect)dirtyRect { [self.cell drawWithFrame:self.bounds inView:self]; }
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
- (NSSize)intrinsicContentSize { return NSMakeSize(89, 28); }
- (void)applyMousePosition:(NSEvent *)event
{
    CGFloat x = [self convertPoint:event.locationInWindow fromView:nil].x-1.5;
    self.doubleValue = MAX(0, MIN(2, x <= 60 ? x/60 : 1+(x-60)/26));
    [self sendAction:self.action to:self.target];
    self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)event
{
    if (!self.enabled) return;
    [self.window makeFirstResponder:self];
    if (event.clickCount == 2) {
        self.doubleValue = 1;
        [self sendAction:self.action to:self.target];
        return;
    }
    [self applyMousePosition:event];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];
        [self applyMousePosition:next];
        if (next.type == NSEventTypeLeftMouseUp) break;
    }
}
- (void)scrollWheel:(NSEvent *)event
{
    self.doubleValue = MAX(0, MIN(2, self.doubleValue + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? .002 : .025)));
    [self sendAction:self.action to:self.target];
}
@end

@interface VLCRedesignPlayerChrome ()
@property (weak) VLCMainVideoViewController *videoController;
@property (weak) NSView *videoContainer;
@property NSView *topBar;
@property NSView *bottomBar;
@property NSArray<VLCPlayerIconButton *> *buttons;
@property VLCPlayerIconButton *previousButton;
@property VLCPlayerIconButton *playButton;
@property VLCPlayerIconButton *nextButton;
@property VLCPlayerIconButton *menuButton;
@property VLCPlayerIconButton *browserButton;
@property VLCPlayerIconButton *folderButton;
@property VLCPlayerIconButton *minimizeButton;
@property VLCPlayerIconButton *maximizeButton;
@property VLCPlayerIconButton *fullscreenButton;
@property VLCPlayerIconButton *closeButton;
@property VLCPlayerIconButton *muteButton;
@property VLCPlayerIconButton *audioButton;
@property VLCPlayerIconButton *subtitlesButton;
@property VLCPlayerIconButton *settingsButton;
@property VLCPlayerIconButton *queueButton;
@property NSImageView *logo;
@property NSImageView *divider;
@property VLCRedesignAlignedLabel *titleLabel;
@property VLCRedesignAlignedLabel *folderLabel;
@property VLCPlayerTimeButton *elapsedButton;
@property VLCPlayerTimeButton *durationButton;
@property VLCPlayerSeekSlider *seekSlider;
@property VLCPlayerVolumeSlider *volumeSlider;
@property NSTimer *visibilityTimer;
@property BOOL showRemaining;
@property BOOL menuOpen;
@property VLCRedesignTrackPanel *trackPanel;
@property id panelEventMonitor;
@end

@implementation VLCRedesignPlayerChrome
- (BOOL)isFlipped { return YES; }

- (instancetype)initWithVideoController:(VLCMainVideoViewController *)controller
{
    self = [super initWithFrame:controller.view.bounds];
    if (!self) return nil;
    _videoController = controller;
    self.wantsLayer = YES;
    _topBar = [[VLCPlayerBar alloc] init];
    _bottomBar = [[VLCPlayerBar alloc] init];
    _topBar.wantsLayer = _bottomBar.wantsLayer = YES;
    [self addSubview:_topBar];
    [self addSubview:_bottomBar];
    _logo = [[NSImageView alloc] init];
    _divider = [[NSImageView alloc] init];
    [_topBar addSubview:_logo];
    [_topBar addSubview:_divider];
    _titleLabel = [self label:@"VLC Media Player" size:14 alignment:NSTextAlignmentCenter];
    _folderLabel = [self label:@"" size:14 alignment:NSTextAlignmentLeft];
    [_topBar addSubview:_titleLabel];
    [_topBar addSubview:_folderLabel];
    _menuButton = [self button:@"menu" label:_NS("Player menu") action:@selector(openMainMenu:) parent:_topBar];
    _browserButton = [self button:@"sidebar" label:_NS("Show library") action:@selector(openLibrary:) parent:_topBar];
    _folderButton = [self button:@"folder" label:_NS("Open containing folder") action:@selector(openFolder:) parent:_topBar];
    _minimizeButton = [self button:@"minimize" label:_NS("Minimize") action:@selector(minimize:) parent:_topBar];
    _maximizeButton = [self button:@"maximize" label:_NS("Zoom window") action:@selector(zoom:) parent:_topBar];
    _fullscreenButton = [self button:@"fullscreen" label:_NS("Enter fullscreen") action:@selector(fullscreen:) parent:_topBar];
    _closeButton = [self button:@"close" label:_NS("Close window") action:@selector(close:) parent:_topBar];
    _previousButton = [self button:@"previous" label:_NS("Previous item") action:@selector(previous:) parent:_bottomBar];
    _playButton = [self button:@"play" label:_NS("Play") action:@selector(play:) parent:_bottomBar];
    _playButton.transport = YES;
    _nextButton = [self button:@"next" label:_NS("Next item") action:@selector(next:) parent:_bottomBar];
    _muteButton = [self button:@"speaker" label:_NS("Mute") action:@selector(mute:) parent:_bottomBar];
    _audioButton = [self button:@"audio" label:_NS("Audio tracks and devices") action:@selector(openAudio:) parent:_bottomBar];
    _subtitlesButton = [self button:@"subtitles" label:_NS("Subtitles") action:@selector(openSubtitles:) parent:_bottomBar];
    _settingsButton = [self button:@"settings" label:_NS("Playback settings") action:@selector(openSettings:) parent:_bottomBar];
    _queueButton = [self button:@"queue" label:_NS("Play queue") action:@selector(openQueue:) parent:_bottomBar];
    _elapsedButton = [self timeButton:_NS("Jump to time") action:@selector(jumpToTime:)];
    _durationButton = [self timeButton:_NS("Toggle duration and remaining time") action:@selector(toggleRemaining:)];
    _seekSlider = [[VLCPlayerSeekSlider alloc] initWithFrame:NSZeroRect];
    _seekSlider.minValue = 0; _seekSlider.maxValue = 1;
    _seekSlider.continuous = YES; _seekSlider.scrollable = YES;
    _seekSlider.target = self; _seekSlider.action = @selector(seek:);
    _seekSlider.accessibilityLabel = _NS("Playback position");
    __weak typeof(self) weakSelf = self;
    _seekSlider.didFinishSeeking = ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.player.seekable)
            [strongSelf.player setPositionPrecise:strongSelf.seekSlider.floatValue];
    };
    _volumeSlider = [[VLCPlayerVolumeSlider alloc] initWithFrame:NSZeroRect];
    _volumeSlider.minValue = 0; _volumeSlider.maxValue = VLCVolumeMaximum;
    _volumeSlider.continuous = YES;
    _volumeSlider.target = self; _volumeSlider.action = @selector(volume:);
    _volumeSlider.accessibilityLabel = _NS("Volume");
    [_bottomBar addSubview:_seekSlider];
    [_bottomBar addSubview:_volumeSlider];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[VLCPlayerStateChanged, VLCPlayerCurrentMediaItemChanged, VLCPlayerMetadataChangedForCurrentMedia,
                             VLCPlayerCapabilitiesChanged, VLCPlayerLengthChanged, VLCPlayerVolumeChanged, VLCPlayerMuteChanged,
                             VLCPlayerFullscreenChanged, VLCPlayerTrackListChanged, VLCPlaybackHasPreviousChanged,
                             VLCPlaybackHasNextChanged, VLCRedesignAppearanceChanged])
        [center addObserver:self selector:@selector(playerChanged:) name:name object:nil];
    [center addObserver:self selector:@selector(timeChanged:) name:VLCPlayerTimeAndPositionChanged object:nil];
    _visibilityTimer = [NSTimer scheduledTimerWithTimeInterval:.2 repeats:YES block:^(NSTimer * __unused timer) {
        [weakSelf updateVisibility];
    }];
    [self updatePlayer];
    return self;
}

- (VLCPlayerController *)player { return VLCMain.sharedInstance.playQueueController.playerController; }
- (void)dealloc
{
    [_visibilityTimer invalidate];
    if (_panelEventMonitor) [NSEvent removeMonitor:_panelEventMonitor];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (VLCRedesignAlignedLabel *)label:(NSString *)text size:(CGFloat)size alignment:(NSTextAlignment)alignment
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:text];
    label.font = [VLCRedesignAppearance fontOfSize:size weight:NSFontWeightRegular];
    label.alignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}
- (VLCPlayerIconButton *)button:(NSString *)role label:(NSString *)label action:(SEL)action parent:(NSView *)parent
{
    VLCPlayerIconButton *button = [[VLCPlayerIconButton alloc] init];
    button.assetRole = role;
    button.title = @"";
    button.bordered = NO;
    button.target = self;
    button.action = action;
    button.toolTip = button.accessibilityLabel = label;
    [parent addSubview:button];
    self.buttons = [(self.buttons ?: @[]) arrayByAddingObject:button];
    return button;
}
- (VLCPlayerTimeButton *)timeButton:(NSString *)label action:(SEL)action
{
    VLCPlayerTimeButton *button = [[VLCPlayerTimeButton alloc] init];
    button.bordered = NO;
    button.target = self; button.action = action;
    button.toolTip = button.accessibilityLabel = label;
    [_bottomBar addSubview:button];
    return button;
}
- (void)mountVideoView:(NSView *)videoView
{
    [videoView removeFromSuperview];
    videoView.translatesAutoresizingMaskIntoConstraints = YES;
    videoView.autoresizingMask = NSViewNotSizable;
    [self addSubview:videoView positioned:NSWindowBelow relativeTo:_topBar];
    _videoContainer = videoView;
    self.needsLayout = YES;
}
- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
    BOOL narrow = width < 920;
    BOOL compact = width < 560;
    CGFloat barHeight = compact ? 138 : narrow ? 96 : 54;
    _topBar.frame = NSMakeRect(0, 0, width, 40);
    _bottomBar.frame = NSMakeRect(0, MAX(40, height-barHeight), width, barHeight);
    BOOL fullscreen = self.player.fullscreen;
    if (_videoContainer.superview == self) {
        _videoContainer.frame = fullscreen ? self.bounds : NSMakeRect(10, 40, MAX(0,width-20), MAX(0,height-40-barHeight));
        _videoContainer.wantsLayer = YES;
        _videoContainer.layer.cornerRadius = fullscreen ? 0 : 12;
        _videoContainer.layer.masksToBounds = YES;
    }
    _logo.frame = NSMakeRect(13, 8, 24, 24);
    _menuButton.frame = NSMakeRect(49, 6, 28, 28);
    _browserButton.frame = NSMakeRect(87, 6, 28, 28);
    _divider.frame = NSMakeRect(115, 8, 24, 24);
    _folderButton.frame = NSMakeRect(139, 6, 28, 28);
    _folderLabel.frame = NSMakeRect(171, 6, MIN(116, MAX(0,width/2-310)), 28);
    _titleLabel.hidden = _folderButton.hidden = _folderLabel.hidden = _divider.hidden = width < 600;
    CGFloat titleMargin = MIN(310, width*.36);
    _titleLabel.frame = NSMakeRect(titleMargin, 6, MAX(0,width-2*titleMargin), 28);
    NSArray *windowButtons = @[_minimizeButton,_maximizeButton,_fullscreenButton,_closeButton];
    for (NSUInteger i=0;i<windowButtons.count;i++)
        ((NSButton *)windowButtons[i]).frame = NSMakeRect(width-150+i*36, 6, 36, 28);
    CGFloat pad = narrow ? 12 : 20, gap = narrow ? 12 : 20;
    CGFloat y = narrow ? 54 : 11;
    _previousButton.frame = NSMakeRect(pad, y+2, 30, 28);
    _playButton.frame = NSMakeRect(pad+38, y+2, 54, 28);
    _nextButton.frame = NSMakeRect(pad+100, y+2, 30, 28);
    CGFloat right = width-pad;
    _queueButton.frame = NSMakeRect(right-30, y, 30, 32); right-=30+gap;
    _settingsButton.frame = NSMakeRect(right-30, y, 30, 32); right-=42;
    _subtitlesButton.frame = NSMakeRect(right-30, y, 30, 32); right-=42;
    _audioButton.frame = NSMakeRect(right-30, y, 30, 32); right-=30+gap;
    _volumeSlider.frame = NSMakeRect(right-89, y+2, 89, 28); right-=97;
    _muteButton.frame = NSMakeRect(right-24, y+4, 24, 24); right-=24+gap;
    CGFloat seekStart = narrow ? pad : pad+130+gap;
    CGFloat seekEnd = narrow ? width-pad : right;
    CGFloat seekY = narrow ? 12 : y+2;
    CGFloat timeWidth = narrow ? 76 : 76;
    _elapsedButton.frame = NSMakeRect(seekStart, seekY, timeWidth, 28);
    _durationButton.frame = NSMakeRect(seekEnd-timeWidth, seekY, timeWidth, 28);
    _seekSlider.frame = NSMakeRect(seekStart+timeWidth+8, seekY, MAX(0,seekEnd-seekStart-2*timeWidth-16), 28);
    if (compact) {
        _queueButton.frame = NSMakeRect(width-pad-30, 54, 30, 32);
        _settingsButton.frame = NSMakeRect(width-pad-72, 54, 30, 32);
        _muteButton.frame = NSMakeRect(pad, 100, 24, 24);
        _volumeSlider.frame = NSMakeRect(pad+32, 98, 89, 28);
        _audioButton.frame = NSMakeRect(width-pad-72, 96, 30, 32);
        _subtitlesButton.frame = NSMakeRect(width-pad-30, 96, 30, 32);
    }
    if (_trackPanel) {
        CGFloat panelHeight = MIN(524, MAX(180,height-barHeight-60));
        _trackPanel.frame = NSMakeRect(MAX(10,width-420),MAX(40,height-barHeight-20-panelHeight),MIN(400,MAX(0,width-40)),panelHeight);
    }
    _bottomBar.needsDisplay = YES;
    for (NSView *control in _bottomBar.subviews) control.needsDisplay = YES;
    [self updateVisibility];
}
- (void)playerChanged:(NSNotification *)notification { [self updatePlayer]; }
- (void)timeChanged:(NSNotification *)notification
{
    VLCPlayerController *player = self.player;
    if (!_seekSlider.dragging) _seekSlider.doubleValue = MAX(0, MIN(1, player.position));
    vlc_tick_t length = player.length;
    _seekSlider.mediaDuration = length;
    _elapsedButton.title = [self timeString:player.currentMedia ? MAX(0,player.time) : -1];
    _durationButton.title = length > 0 ? (self.showRemaining ? [@"−" stringByAppendingString:[self timeString:MAX(0,length-player.time)]] : [self timeString:length]) : @"--:--:--";
    _elapsedButton.needsDisplay = _durationButton.needsDisplay = YES;
}
- (NSString *)timeString:(vlc_tick_t)time
{
    if (time < 0) return @"--:--:--";
    int64_t seconds = SEC_FROM_VLC_TICK(time);
    return [NSString stringWithFormat:@"%02lld:%02lld:%02lld",seconds/3600,(seconds/60)%60,seconds%60];
}
- (void)updatePlayer
{
    VLCPlayerController *player = self.player;
    VLCPlayQueueController *queue = VLCMain.sharedInstance.playQueueController;
    self.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    _topBar.layer.backgroundColor = _bottomBar.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    _titleLabel.textColor = _folderLabel.textColor = VLCRedesignAppearance.subduedColor;
    for (VLCPlayerIconButton *button in self.buttons) {
        button.image = VLCPlayerAsset(button.assetRole);
        button.needsDisplay = YES;
    }
    _logo.image = VLCPlayerAsset(@"logo");
    _divider.image = VLCPlayerAsset(@"divider");
    _titleLabel.stringValue = player.currentMedia.name ?: @"VLC Media Player";
    NSURL *url = player.URLOfCurrentMediaItem;
    _folderLabel.stringValue = url.isFileURL ? url.URLByDeletingLastPathComponent.lastPathComponent : _NS("Library");
    _folderButton.enabled = url.isFileURL;
    _folderButton.toolTip = url.isFileURL ? url.URLByDeletingLastPathComponent.path : _NS("No local media folder");
    _playButton.playing = player.playerState == VLC_PLAYER_STATE_PLAYING;
    _playButton.toolTip = _playButton.accessibilityLabel = _playButton.playing ? _NS("Pause") : _NS("Play");
    _previousButton.enabled = queue.hasPreviousPlayQueueItem;
    _nextButton.enabled = queue.hasNextPlayQueueItem;
    _seekSlider.enabled = player.seekable && player.length > 0;
    _elapsedButton.enabled = player.seekable;
    _volumeSlider.doubleValue = player.mute ? 0 : player.volume;
    _volumeSlider.toolTip = [NSString stringWithFormat:_NS("Volume: %i %%"),(int)round(player.volume*100)];
    _muteButton.selected = player.mute;
    _muteButton.toolTip = _muteButton.accessibilityLabel = player.mute ? _NS("Unmute") : _NS("Mute");
    _fullscreenButton.toolTip = _fullscreenButton.accessibilityLabel = player.fullscreen ? _NS("Exit fullscreen") : _NS("Enter fullscreen");
    _minimizeButton.enabled = _maximizeButton.enabled = !player.fullscreen;
    _volumeSlider.needsDisplay = _seekSlider.needsDisplay = YES;
    self.needsLayout = YES;
    [self timeChanged:nil];
}
- (BOOL)mouseOnControls
{
    NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    return NSPointInRect(point,_topBar.frame) || NSPointInRect(point,_bottomBar.frame) || self.menuOpen || self.trackPanel != nil;
}
- (void)updateVisibility
{
    if (!self.window || self.hidden || !self.window.visible) return;
    NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    BOOL fullscreen = self.player.fullscreen;
    BOOL inside = NSPointInRect(point,self.bounds);
    if ([self.window isKindOfClass:VLCLibraryWindow.class]) {
        BOOL selected = !((VLCLibraryWindow *)self.window).splitViewController.multifunctionSidebarItem.collapsed;
        if (_queueButton.selected != selected) {
            _queueButton.selected = selected;
            _queueButton.needsDisplay = YES;
        }
    }
    _topBar.hidden = fullscreen && !self.menuOpen && !self.trackPanel && !(inside && point.y < 56);
    _bottomBar.hidden = fullscreen && !self.menuOpen && !self.trackPanel && !(inside && point.y > NSHeight(self.bounds)-NSHeight(_bottomBar.frame)-16);
}

#pragma mark - Real player and window actions
- (void)play:(id)sender { [self.player togglePlayPause]; }
- (void)previous:(id)sender { [VLCMain.sharedInstance.playQueueController playPreviousItem]; }
- (void)next:(id)sender { [VLCMain.sharedInstance.playQueueController playNextItem]; }
- (void)seek:(NSSlider *)sender
{
    if (!self.player.seekable) return;
    if (_seekSlider.dragging) [self.player setPositionFast:sender.floatValue];
    else [self.player setPositionPrecise:sender.floatValue];
}
- (void)volume:(NSSlider *)sender
{
    if (self.player.mute) [self.player toggleMute];
    self.player.volume = sender.floatValue;
}
- (void)mute:(id)sender { [self.player toggleMute]; }
- (void)fullscreen:(id)sender { [self.player toggleFullscreen]; }
- (void)minimize:(id)sender { [self.window performMiniaturize:sender]; }
- (void)zoom:(id)sender { [self.window performZoom:sender]; }
- (void)close:(id)sender
{
    NSWindow *window = [VLCMain.sharedInstance.voutProvider videoWindowForVoutView:self.videoController.voutView] ?: self.window;
    [window performClose:sender];
}
- (void)jumpToTime:(id)sender { [VLCMain.sharedInstance.mainMenu goToSpecificTime:sender]; }
- (void)toggleRemaining:(id)sender { self.showRemaining = !self.showRemaining; [self timeChanged:nil]; }
- (void)openQueue:(id)sender
{
    if ([self.window isKindOfClass:VLCLibraryWindow.class])
        [self.videoController togglePlayQueue:sender];
    else
        [VLCMain.sharedInstance.mainMenu showPlayQueue:sender];
}
- (void)openLibrary:(id)sender { [self.videoController returnToLibrary:sender]; }
- (void)openFolder:(id)sender
{
    NSURL *url = self.player.URLOfCurrentMediaItem;
    if (url.isFileURL) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
}
- (void)showMenu:(NSMenu *)menu sender:(NSView *)sender
{
    self.menuOpen = YES;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSHeight(sender.bounds)) inView:sender];
    self.menuOpen = NO;
    [self updateVisibility];
}
- (void)closeTrackPanel
{
    [_trackPanel removeFromSuperview];
    _trackPanel = nil;
    _audioButton.selected = _subtitlesButton.selected = NO;
    _audioButton.needsDisplay = _subtitlesButton.needsDisplay = YES;
    if (_panelEventMonitor) { [NSEvent removeMonitor:_panelEventMonitor]; _panelEventMonitor = nil; }
    [self updateVisibility];
}
- (void)showTracks:(NSInteger)tab
{
    if (_trackPanel && _trackPanel.selectedTab == tab) { [self closeTrackPanel]; return; }
    if (!_trackPanel) {
        _trackPanel = [[VLCRedesignTrackPanel alloc] init];
        __weak typeof(self) weakSelf = self;
        _trackPanel.selectionChanged = ^(NSInteger selected) {
            weakSelf.audioButton.selected = selected == 1;
            weakSelf.subtitlesButton.selected = selected == 2;
            weakSelf.audioButton.needsDisplay = weakSelf.subtitlesButton.needsDisplay = YES;
        };
        _trackPanel.showPreferences = ^{
            [weakSelf closeTrackPanel];
            [VLCMain.sharedInstance.mainMenu showPreferences:nil];
        };
        [self addSubview:_trackPanel];
        _panelEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || event.window != strongSelf.window) return event;
            if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
                [strongSelf closeTrackPanel]; return nil;
            }
            if (event.type == NSEventTypeLeftMouseDown) {
                NSPoint point = [strongSelf convertPoint:event.locationInWindow fromView:nil];
                NSPoint bottom = [strongSelf.bottomBar convertPoint:event.locationInWindow fromView:nil];
                if (!NSPointInRect(point,strongSelf.trackPanel.frame) &&
                    !NSPointInRect(bottom,strongSelf.audioButton.frame) && !NSPointInRect(bottom,strongSelf.subtitlesButton.frame))
                    [strongSelf closeTrackPanel];
            }
            return event;
        }];
    }
    _trackPanel.selectedTab = tab;
    _audioButton.selected = tab == 1;
    _subtitlesButton.selected = tab == 2;
    _audioButton.needsDisplay = _subtitlesButton.needsDisplay = YES;
    self.needsLayout = YES;
    [self updateVisibility];
}
- (void)openAudio:(NSView *)sender { [self showTracks:1]; }
- (void)openSubtitles:(NSView *)sender { [self showTracks:2]; }
- (void)addMenuItem:(NSString *)title action:(SEL)action target:(id)target menu:(NSMenu *)menu
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    [menu addItem:item];
}
- (void)openSettings:(NSView *)sender
{
    VLCMainMenu *main = VLCMain.sharedInstance.mainMenu;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:_NS("Playback settings")];
    for (NSArray *entry in @[@[_NS("Playback"), main.controlsMenu],@[_NS("Video"),main.videoMenu],@[_NS("Audio"),main.audioMenu],@[_NS("Subtitles"),main.subtitlesMenu]]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:NULL keyEquivalent:@""];
        item.submenu = [entry[1] copy];
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    [self addMenuItem:_NS("Picture in Picture") action:@selector(pictureInPicture:) target:self menu:menu];
    [self addMenuItem:_NS("Bookmarks…") action:@selector(showBookmarks:) target:main menu:menu];
    [self addMenuItem:_NS("Track Synchronization…") action:@selector(showTrackSynchronization:) target:main menu:menu];
    [self addMenuItem:_NS("Media Information…") action:@selector(showInformationPanel:) target:main menu:menu];
    [self addMenuItem:_NS("Preferences…") action:@selector(showPreferences:) target:main menu:menu];
    [self showMenu:menu sender:sender];
}
- (void)pictureInPicture:(id)sender { [self.player togglePictureInPicture]; }
- (void)openMainMenu:(NSView *)sender
{
    VLCMainMenu *main = VLCMain.sharedInstance.mainMenu;
    NSMenu *menu = [main.fileMenu copy];
    [menu addItem:NSMenuItem.separatorItem];
    [self addMenuItem:_NS("Stop") action:@selector(stop:) target:main menu:menu];
    [self addMenuItem:_NS("Picture in Picture") action:@selector(pictureInPicture:) target:self menu:menu];
    [self addMenuItem:_NS("Show Library") action:@selector(openLibrary:) target:self menu:menu];
    [self addMenuItem:_NS("Preferences…") action:@selector(showPreferences:) target:main menu:menu];
    [self showMenu:menu sender:sender];
}
@end
