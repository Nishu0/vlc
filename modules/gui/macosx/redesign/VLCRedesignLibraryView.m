/*****************************************************************************
 * VLCRedesignLibraryView.m: Full-window redesigned media library
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignLibraryView.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignIconButton.h"
#import "VLCRedesignMiniPlayer.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "menus/VLCMainMenu.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibraryWindow.h"
#import "library/media-source/VLCLibraryMediaSourceViewController.h"
#import "library/media-source/VLCMediaSourceBaseDataSource.h"
#import "library/media-source/VLCMediaSource.h"
#import "library/media-source/VLCMediaSourceDataSource.h"
#import "library/VLCInputItem.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "windows/video/VLCMainVideoViewController.h"

/* Window title bar: dragging it moves the window and a double click zooms,
 * like the native title bar it replaces. */
@interface VLCLibraryTitleBar : NSView
@end
@implementation VLCLibraryTitleBar

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

- (void)mouseUp:(NSEvent *)event
{
    if (event.clickCount == 2)
        [self.window performZoom:self];
    else
        [super mouseUp:event];
}

@end

@interface VLCRedesignLibraryView ()
@property VLCLibraryTitleBar *topBar;
@property NSImageView *logo;
@property VLCRedesignAlignedLabel *titleLabel;
@property NSArray<VLCPlayerIconButton *> *buttons;
@property VLCRedesignMiniPlayer *miniPlayer;
@end

@implementation VLCRedesignLibraryView

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
    _browser = [[VLCRedesignCompactBrowser alloc] init];
    _browser.fullLibrary = YES;
    _browser.openNetworkSource = ^(VLCMediaSource *source) {
        /* Network shares still browse in the classic media source view */
        VLCLibraryWindow *window = VLCMain.sharedInstance.libraryWindow;
        [window presentClassicLibrary];
        window.librarySegmentType = VLCLibraryStreamsSegmentType;
        VLCLibraryMediaSourceViewController *controller = (id)window.librarySegmentViewController;
        if ([controller isKindOfClass:VLCLibraryMediaSourceViewController.class])
            [controller.baseDataSource configureChildDataSourceWithNode:source.rootNode andMediaSource:source];
    };
    [self addSubview:_browser];
    _topBar = [[VLCLibraryTitleBar alloc] init];
    _topBar.wantsLayer = YES;
    [self addSubview:_topBar];
    _logo = [[NSImageView alloc] init];
    [_topBar addSubview:_logo];
    _titleLabel = [VLCRedesignAlignedLabel labelWithString:@"VLC Media Player"];
    _titleLabel.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    _titleLabel.alignment = NSTextAlignmentCenter;
    [_topBar addSubview:_titleLabel];
    NSArray *roles = @[ @"menu", @"minimize", @"maximize", @"fullscreen", @"close" ];
    NSArray *labels = @[ _NS("Main menu"), _NS("Minimize"), _NS("Zoom window"), _NS("Full Screen"), _NS("Close window") ];
    NSArray *actions = @[ @"openMainMenu:", @"minimize:", @"zoom:", @"fullscreen:", @"close:" ];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < roles.count; i++) {
        VLCPlayerIconButton *button = [[VLCPlayerIconButton alloc] init];
        button.assetRole = roles[i];
        button.title = @"";
        button.bordered = NO;
        button.target = self;
        button.action = NSSelectorFromString(actions[i]);
        button.toolTip = button.accessibilityLabel = labels[i];
        [_topBar addSubview:button];
        [buttons addObject:button];
    }
    _buttons = buttons;
    [self setupMiniPlayer];
    [self updateAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateAppearance)
                                               name:VLCRedesignAppearanceChanged
                                             object:nil];
    return self;
}

- (void)setupMiniPlayer
{
    _miniPlayer = [[VLCRedesignMiniPlayer alloc] initWithFrame:NSZeroRect];
    _miniPlayer.hidden = YES;
    __weak typeof(self) weakSelf = self;
    _miniPlayer.openPlayer = ^{
        [VLCMain.sharedInstance.libraryWindow enableVideoPlaybackAppearance];
    };
    _miniPlayer.openQueue = ^{
        VLCLibraryWindow *window = VLCMain.sharedInstance.libraryWindow;
        [window enableVideoPlaybackAppearance];
        [window.videoViewController togglePlayQueue:nil];
    };
    _miniPlayer.cornerChanged = ^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = .18;
            context.allowsImplicitAnimation = YES;
            [weakSelf layoutMiniPlayer];
        }];
    };
    [self addSubview:_miniPlayer];
    for (NSString *name in @[ VLCPlayerStateChanged, VLCPlayerCurrentMediaItemChanged ])
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(playbackChanged:)
                                                   name:name
                                                 object:nil];
    [self playbackChanged:nil];
}

- (void)playbackChanged:(NSNotification *)notification
{
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    BOOL playing = player.currentMedia != nil && player.playerState != VLC_PLAYER_STATE_STOPPED;
    _miniPlayer.hidden = !playing;
    _titleLabel.stringValue = playing && player.currentMedia.name.length ? player.currentMedia.name : @"VLC Media Player";
    self.needsLayout = YES;
}

- (void)setMiniPlayerVideoView:(NSView *)videoView
{
    [_miniPlayer setVideoView:videoView];
}

- (void)layoutMiniPlayer
{
    NSSize size = VLCRedesignMiniPlayerSize;
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
    /* Smaller windows get a proportionally smaller card */
    CGFloat scale = MAX(.6, MIN(1, MIN(width * .3 / size.width, height * .45 / size.height)));
    size = NSMakeSize(floor(size.width * scale), floor(size.height * scale));
    CGFloat x = _miniPlayer.leftCorner ? 6 : width - size.width - 6;
    _miniPlayer.frame = NSMakeRect(x, height - size.height - 6, size.width, size.height);
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)updateAppearance
{
    self.appearance = VLCRedesignAppearance.themeAppearance;
    self.layer.backgroundColor = VLCRedesignAppearance.backgroundColor.CGColor;
    _topBar.layer.backgroundColor = VLCRedesignAppearance.raisedColor.CGColor;
    _titleLabel.textColor = VLCRedesignAppearance.subduedColor;
    _logo.image = VLCPlayerAsset(@"logo");
    for (VLCPlayerIconButton *button in _buttons) {
        button.image = VLCPlayerAsset(button.assetRole);
        button.needsDisplay = YES;
    }
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
    _topBar.frame = NSMakeRect(0, 0, width, 40);
    _browser.frame = NSMakeRect(0, 40, width, MAX(0, height - 40));
    _logo.frame = NSMakeRect(13, 8, 24, 24);
    _buttons[0].frame = NSMakeRect(49, 6, 28, 28);
    for (NSUInteger i = 1; i < _buttons.count; i++)
        _buttons[i].frame = NSMakeRect(width - 150 + (i - 1) * 36, 6, 36, 28);
    CGFloat margin = MIN(310, width * .3);
    _titleLabel.frame = NSMakeRect(margin, 6, MAX(0, width - 2 * margin), 28);
    _titleLabel.hidden = width < 480;
    [self layoutMiniPlayer];
}

- (void)showSection:(VLCRedesignBrowserSection)section folder:(NSURL *)folder grid:(BOOL)grid
{
    /* The full library keeps its own grid or list choice rather than the compact browser's */
    if (folder.isFileURL)
        [_browser browseFolder:folder];
    else
        [_browser showSection:section];
}

#pragma mark - Title bar actions

- (void)openMainMenu:(NSView *)sender
{
    VLCMainMenu *main = VLCMain.sharedInstance.mainMenu;
    NSMenu *menu = [main.fileMenu copy];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *preferences = [menu addItemWithTitle:_NS("Preferences…")
                                              action:@selector(showPreferences:)
                                       keyEquivalent:@""];
    preferences.target = main;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds)) inView:sender];
}

- (void)minimize:(id)sender
{
    [self.window performMiniaturize:sender];
}

- (void)zoom:(id)sender
{
    [self.window performZoom:sender];
}

- (void)fullscreen:(id)sender
{
    [self.window toggleFullScreen:sender];
}

- (void)close:(id)sender
{
    [self.window performClose:sender];
}

@end
