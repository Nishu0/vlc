/*****************************************************************************
 * VLCRedesignTrackPanel.m: In-player track and audio device selection
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import "VLCRedesignTrackPanel.h"
#import "VLCRedesignPanelButton.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import <vlc_aout.h>
#import <vlc_hash.h>
#import <vlc_strings.h>
#import "library/VLCInputItem.h"
#import "menus/VLCMainMenu.h"

static NSImage *VLCTrackAsset(NSString *role)
{
    return VLCRedesignPanelImage([@"VLC-redesign-tracks-" stringByAppendingString:role]);
}

@interface VLCTrackDocument : NSView
@end
@implementation VLCTrackDocument

- (BOOL)isFlipped
{
    return YES;
}

@end

@interface VLCRedesignTrackPanel ()
@property NSArray<VLCRedesignPanelButton *> *tabs;
@property NSView *header;
@property VLCRedesignAlignedLabel *trackHeading;
@property VLCRedesignAlignedLabel *deviceHeading;
@property NSImageView *divider;
@property VLCRedesignPanelButton *refreshButton;
@property VLCRedesignPanelButton *editButton;
@property NSDictionary<NSString *, NSURL *> *externalURLs;
@property VLCRedesignPanelButton *preferencesButton;
@property NSScrollView *bodyScroll;
@property NSScrollView *tracksScroll;
@property NSScrollView *devicesScroll;
@property NSArray<VLCRedesignPanelButton *> *trackRows;
@property NSArray<VLCRedesignPanelButton *> *deviceRows;
@end

@implementation VLCRedesignTrackPanel

- (BOOL)isFlipped
{
    return YES;
}

- (VLCPlayerController *)player
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[VLCRedesignAppearance colorWithRGB:0x0E0E0E] colorWithAlphaComponent:.95].CGColor;
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = YES;
    _header = [[VLCTrackDocument alloc] init];
    _header.wantsLayer = YES;
    _header.layer.backgroundColor = [VLCRedesignAppearance colorWithRGB:0x090909].CGColor;
    [self addSubview:_header];
    __weak typeof(self) weakSelf = self;
    NSMutableArray *tabs = [NSMutableArray array];
    NSArray *titles = @[ _NS("Video"), _NS("Audio"), _NS("Subtitles") ];
    for (NSInteger i = 0; i < 3; i++) {
        VLCRedesignPanelButton *tab = [[VLCRedesignPanelButton alloc] init];
        tab.tab = YES;
        tab.title = titles[i];
        tab.accessibilityLabel = titles[i];
        tab.activate = ^{
            weakSelf.selectedTab = i;
        };
        [_header addSubview:tab];
        [tabs addObject:tab];
    }
    _tabs = tabs;
    _trackHeading = [self heading:_NS("Embedded Tracks")];
    _deviceHeading = [self heading:_NS("Output Device")];
    _divider = [[NSImageView alloc] init];
    _divider.image = VLCTrackAsset(@"divider");
    _divider.imageScaling = NSImageScaleNone;
    [self addSubview:_divider];
    _refreshButton = [[VLCRedesignPanelButton alloc] init];
    _refreshButton.title = @"";
    _refreshButton.image = VLCTrackAsset(@"refresh");
    _refreshButton.toolTip = _refreshButton.accessibilityLabel = _NS("Refresh audio devices");
    _refreshButton.activate = ^{
        [weakSelf refreshOrImport];
    };
    [self addSubview:_refreshButton];
    _editButton = [[VLCRedesignPanelButton alloc] init];
    _editButton.title = @"";
    _editButton.image = VLCTrackAsset(@"edit");
    _editButton.toolTip = _editButton.accessibilityLabel = _NS("Open selected external subtitle in a text editor");
    _editButton.activate = ^{
        [weakSelf editExternalSubtitle];
    };
    [self addSubview:_editButton];
    _preferencesButton = [[VLCRedesignPanelButton alloc] init];
    _preferencesButton.footer = YES;
    _preferencesButton.title = _NS("Show Preferences");
    _preferencesButton.activate = ^{
        if (weakSelf.showPreferences)
            weakSelf.showPreferences();
    };
    [self addSubview:_preferencesButton];
    _tracksScroll = [self scrollView];
    _devicesScroll = [self scrollView];
    _bodyScroll = [self scrollView];
    for (NSView *view in
         @[ _trackHeading, _deviceHeading, _divider, _refreshButton, _editButton, _tracksScroll, _devicesScroll ]) {
        [view removeFromSuperview];
        [_bodyScroll.documentView addSubview:view];
    }
    for (NSString *name in @[
             VLCPlayerCurrentMediaItemChanged, VLCPlayerTrackListChanged, VLCPlayerTrackSelectionChanged,
             VLCPlayerStateChanged
         ])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged:) name:name object:nil];
    [self refresh];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (VLCRedesignAlignedLabel *)heading:(NSString *)title
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:title];
    label.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    label.textColor = [VLCRedesignAppearance colorWithRGB:0x6B6B6B];
    label.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:label];
    return label;
}

- (NSScrollView *)scrollView
{
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.documentView = [[VLCTrackDocument alloc] init];
    [self addSubview:scroll];
    return scroll;
}

- (void)setSelectedTab:(NSInteger)selectedTab
{
    if (_selectedTab == selectedTab)
        return;
    _selectedTab = selectedTab;
    if (self.selectionChanged)
        self.selectionChanged(selectedTab);
    [self refresh];
    [_tracksScroll.contentView scrollToPoint:NSZeroPoint];
}

- (void)playerChanged:(NSNotification *)notification
{
    [self refresh];
}

- (VLCRedesignPanelButton *)row:(NSString *)title selected:(BOOL)selected action:(void (^)(void))action
{
    VLCRedesignPanelButton *row = [[VLCRedesignPanelButton alloc] init];
    row.title = title;
    row.toolTip = row.accessibilityLabel = title;
    row.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
    row.selectionImage = VLCTrackAsset(@"check");
    row.activate = action;
    return row;
}

/* The input core prefixes associated-track IDs with the MD5 of their URL
 * (InputSourceNew / EsOutCreateStrId). Match that prefix to the input's own
 * associated-media list; captions derived from the main video stay embedded. */
- (NSDictionary<NSString *, NSURL *> *)associatedSubtitleURLs
{
    input_item_t *item = self.player.currentMedia.vlcInputItem;
    if (!item)
        return @{};
    NSMutableArray<NSString *> *uris = [NSMutableArray array];
    vlc_mutex_lock(&item->lock);
    for (int i = 0; i < item->i_slaves; i++) {
        input_item_slave_t *slave = item->pp_slaves[i];
        if (slave->i_type == SLAVE_TYPE_SPU)
            [uris addObject:toNSStr(slave->psz_uri)];
    }
    vlc_mutex_unlock(&item->lock);
    NSMutableDictionary *urls = [NSMutableDictionary dictionary];
    for (NSString *uri in uris) {
        const char *string = uri.UTF8String;
        vlc_hash_md5_t hash;
        char digest[VLC_HASH_MD5_DIGEST_HEX_SIZE];
        vlc_hash_md5_Init(&hash);
        vlc_hash_md5_Update(&hash, string, strlen(string));
        vlc_hash_FinishHex(&hash, digest);
        NSURL *url = [NSURL URLWithString:uri];
        if (url)
            urls[toNSStr(digest)] = url;
    }
    return urls;
}

- (NSURL *)externalURLForTrack:(VLCTrackMetaData *)track
{
    NSString *identifier = toNSStr(vlc_es_id_GetStrId(track.esID));
    return _externalURLs[[identifier componentsSeparatedByString:@"/"].firstObject];
}

- (void)refreshOrImport
{
    if (self.selectedTab != 2) {
        [self refresh];
        return;
    }
    [VLCMain.sharedInstance.mainMenu addSubtitleFile:nil];
    [self refresh];
}

- (void)editExternalSubtitle
{
    for (VLCTrackMetaData *track in self.player.subtitleTracks) {
        NSURL *url = [self externalURLForTrack:track];
        if (!track.selected || !url.isFileURL)
            continue;
        NSURL *editor = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
        if (editor) {
            if (@available(macOS 10.15, *))
                [NSWorkspace.sharedWorkspace openURLs:@[ url ]
                                 withApplicationAtURL:editor
                                        configuration:NSWorkspaceOpenConfiguration.configuration
                                    completionHandler:nil];
            else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [NSWorkspace.sharedWorkspace openFile:url.path withApplication:editor.path];
#pragma clang diagnostic pop
            }
        }
        return;
    }
}

- (void)refresh
{
    NSArray *roles = @[ @"video", @"audio", @"subtitles" ];
    for (NSInteger i = 0; i < 3; i++) {
        BOOL selected = i == self.selectedTab;
        _tabs[i].state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        _tabs[i].image = VLCTrackAsset([roles[i] stringByAppendingString:selected ? @"-on" : @"-off"]);
        _tabs[i].underlineImage =
            VLCTrackAsset(selected ? (i == 0 ? @"tab-line-video" : @"tab-line-audio") : @"tab-line-off");
        _tabs[i].needsDisplay = YES;
    }
    NSResponder *responder = self.window.firstResponder;
    NSString *focusedTrack = [_trackRows containsObject:responder] ? ((NSButton *)responder).title : nil;
    NSString *focusedDevice = [_deviceRows containsObject:responder] ? ((NSButton *)responder).title : nil;
    for (NSView *row in _trackRows)
        [row removeFromSuperview];
    for (NSView *row in _deviceRows)
        [row removeFromSuperview];
    NSArray<VLCTrackMetaData *> *tracks = self.selectedTab == 0   ? self.player.videoTracks
                                          : self.selectedTab == 1 ? self.player.audioTracks
                                                                  : self.player.subtitleTracks;
    enum es_format_category_e category = self.selectedTab == 0 ? VIDEO_ES : self.selectedTab == 1 ? AUDIO_ES : SPU_ES;
    BOOL anySelected = NO;
    for (VLCTrackMetaData *track in tracks)
        anySelected |= track.selected;
    __weak typeof(self) weakSelf = self;
    _externalURLs = [self associatedSubtitleURLs];
    NSMutableArray *externalRows = [NSMutableArray array];
    BOOL canEdit = NO;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[self row:_NS("None")
                        selected:!anySelected
                          action:^{
                              [weakSelf.player unselectTracksFromCategory:category];
                          }]];
    for (VLCTrackMetaData *track in tracks) {
        NSURL *externalURL = self.selectedTab == 2 ? [self externalURLForTrack:track] : nil;
        VLCRedesignPanelButton *row = [self row:externalURL.lastPathComponent ?: track.name
                                       selected:track.selected
                                         action:^{
                                             [weakSelf.player selectTrack:track exclusively:YES];
                                         }];
        [(externalURL ? externalRows : rows) addObject:row];
        if (externalURL.isFileURL && track.selected &&
            [@[ @"srt", @"ass", @"ssa", @"vtt", @"sub", @"txt", @"ttml", @"smi" ]
                containsObject:externalURL.pathExtension.lowercaseString])
            canEdit = YES;
    }
    _trackRows = rows;
    for (VLCRedesignPanelButton *row in rows) {
        row.enabled = self.player.currentMedia != nil;
        [_tracksScroll.documentView addSubview:row];
    }
    NSMutableArray *devices = [NSMutableArray array];
    if (self.selectedTab == 1) {
        audio_output_t *output = self.player.mainAudioOutput;
        if (output) {
            char **ids = NULL, **names = NULL;
            int count = aout_DevicesList(output, &ids, &names);
            char *current = aout_DeviceGet(output);
            for (int i = 0; i < count; i++) {
                NSString *deviceID = toNSStr(ids[i]);
                BOOL selected = current ? !strcmp(current, ids[i]) : i == 0;
                [devices addObject:[self row:toNSStr(names[i])
                                       selected:selected
                                         action:^{
                                             audio_output_t *activeOutput = weakSelf.player.mainAudioOutput;
                                             if (!activeOutput)
                                                 return;
                                             int result = aout_DeviceSet(activeOutput, deviceID.UTF8String);
                                             aout_Release(activeOutput);
                                             if (result != 0)
                                                 NSBeep();
                                             [weakSelf refresh];
                                         }]];
                free(ids[i]);
                free(names[i]);
            }
            free(current);
            free(ids);
            free(names);
            aout_Release(output);
        }
        if (!devices.count) {
            VLCRedesignPanelButton *empty = [self row:_NS("No audio output available") selected:NO action:nil];
            empty.enabled = NO;
            [devices addObject:empty];
        }
    }
    if (self.selectedTab == 2)
        [devices addObjectsFromArray:externalRows];
    _editButton.enabled = canEdit;
    _refreshButton.image = VLCTrackAsset(self.selectedTab == 2 ? @"add" : @"refresh");
    _refreshButton.toolTip = _refreshButton.accessibilityLabel =
        self.selectedTab == 2 ? _NS("Add subtitle files") : _NS("Refresh audio devices");
    _refreshButton.enabled = self.selectedTab != 2 || self.player.currentMedia != nil;
    _deviceHeading.stringValue = self.selectedTab == 2 ? _NS("External Tracks") : _NS("Output Device");
    _deviceRows = devices;
    for (NSView *row in devices)
        [_devicesScroll.documentView addSubview:row];
    self.needsLayout = YES;
    for (VLCRedesignPanelButton *row in _trackRows)
        if (focusedTrack && [row.title isEqualToString:focusedTrack])
            [self.window makeFirstResponder:row];
    for (VLCRedesignPanelButton *row in _deviceRows)
        if (focusedDevice && [row.title isEqualToString:focusedDevice])
            [self.window makeFirstResponder:row];
}

- (void)layoutRows:(NSArray<VLCRedesignPanelButton *> *)rows scroll:(NSScrollView *)scroll
{
    CGFloat width = NSWidth(scroll.contentView.bounds);
    scroll.documentView.frame =
        NSMakeRect(0, 0, width, MAX(NSHeight(scroll.contentView.bounds), (rows.count ? rows.count * 44 - 12 : 0)));
    for (NSUInteger i = 0; i < rows.count; i++)
        rows[i].frame = NSMakeRect(0, i * 44, width, 32);
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
    _header.frame = NSMakeRect(0, 0, width, 50);
    CGFloat tabWidth = (width - 14) / 3;
    for (NSUInteger i = 0; i < 3; i++)
        _tabs[i].frame = NSMakeRect(6 + i * (tabWidth + 1), 0, tabWidth, 50);
    _bodyScroll.frame = NSMakeRect(0, 50, width, MAX(0, height - 122));
    CGFloat bodyHeight = MAX(170, NSHeight(_bodyScroll.contentView.bounds));
    _bodyScroll.documentView.frame = NSMakeRect(0, 0, NSWidth(_bodyScroll.contentView.bounds), bodyHeight);
    width = NSWidth(_bodyScroll.contentView.bounds);
    BOOL audio = self.selectedTab != 0;
    CGFloat headingHeight = audio ? MAX(28, MIN(60, (bodyHeight - 140) / 2)) : 60;
    _trackHeading.frame = NSMakeRect(28, 1, MAX(0, width - 56), headingHeight);
    CGFloat contentEnd = bodyHeight;
    CGFloat trackHeight =
        audio ? MAX(0, (contentEnd - 2 * headingHeight - 2) / 2) : MAX(0, contentEnd - headingHeight - 1);
    _tracksScroll.frame = NSMakeRect(20, headingHeight + 1, MAX(0, width - 40), trackHeight);
    CGFloat deviceY = headingHeight + 2 + trackHeight;
    _deviceHeading.hidden = _refreshButton.hidden = _devicesScroll.hidden = !audio;
    _divider.hidden = self.selectedTab != 1;
    _editButton.hidden = self.selectedTab != 2;
    _divider.frame = NSMakeRect(0, deviceY - 1, width, 1);
    _deviceHeading.frame = NSMakeRect(28, deviceY, MAX(0, width - 90), headingHeight);
    _refreshButton.frame = NSMakeRect(width - 48, deviceY + (headingHeight - 24) / 2, 24, 24);
    _editButton.frame = NSMakeRect(width - 92, deviceY + (headingHeight - 24) / 2, 24, 24);
    _devicesScroll.frame =
        NSMakeRect(20, deviceY + headingHeight, MAX(0, width - 40), MAX(0, contentEnd - deviceY - headingHeight));
    _preferencesButton.frame = NSMakeRect(20, height - 52, MAX(0, width - 40), 32);
    [self layoutRows:_trackRows scroll:_tracksScroll];
    [self layoutRows:_deviceRows scroll:_devicesScroll];
}

@end
