/*****************************************************************************
 * VLCRedesignQueuePanel.m: In-player queue, bookmarks and chapters
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import "VLCRedesignQueuePanel.h"
#import "VLCRedesignPanelButton.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayQueueDataSource.h"
#import "playqueue/VLCPlayQueueModel.h"
#import "playqueue/VLCPlayQueueItem.h"
#import "windows/VLCOpenInputMetadata.h"
#import "views/VLCFileDragRecognisingView.h"
#import "library/VLCLibraryDataTypes.h"
#import "panels/bookmarks/VLCBookmark.h"
#import <vlc_media_library.h>

static NSImage *VLCQueueAsset(NSString *role)
{
    return VLCRedesignPanelImage([@"VLC-redesign-queue-" stringByAppendingString:role]);
}

static NSString *VLCQueueTime(vlc_tick_t time, BOOL milliseconds)
{
    if (time < 0)
        return @"--:--";
    int64_t ms = MS_FROM_VLC_TICK(time), seconds = ms / 1000;
    if (milliseconds)
        return [NSString stringWithFormat:@"%02lld:%02lld:%02lld.%03lld", seconds / 3600, (seconds / 60) % 60,
                                          seconds % 60, ms % 1000];
    if (seconds >= 3600)
        return [NSString stringWithFormat:@"%02lld:%02lld:%02lld", seconds / 3600, (seconds / 60) % 60, seconds % 60];
    return [NSString stringWithFormat:@"%02lld:%02lld", seconds / 60, seconds % 60];
}

@interface VLCQueueHeader : NSView
@end
@implementation VLCQueueHeader

- (BOOL)isFlipped
{
    return YES;
}

@end
@interface VLCQueueTable : NSTableView
@property (copy) void (^activateRow)(void);
@property (copy) void (^removeRow)(void);
@end
@implementation VLCQueueTable

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.activateRow)
            self.activateRow();
    } else if (event.keyCode == 51 || event.keyCode == 117) {
        if (self.removeRow)
            self.removeRow();
    } else
        [super keyDown:event];
}

@end
@interface VLCQueueRow : NSTableRowView
@end
@implementation VLCQueueRow

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    [VLCRedesignAppearance.accentBackingColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0, 2) xRadius:4 yRadius:4] fill];
}

@end
@interface VLCQueueCell : NSTableCellView
@property VLCRedesignAlignedLabel *durationLabel;
@property VLCRedesignAlignedLabel *numberLabel;
@property NSImageView *grip;
@property NSInteger tab;
@end
@implementation VLCQueueCell

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;
    self.textField = [self label];
    [self addSubview:self.textField];
    _durationLabel = [self label];
    _durationLabel.alignment = NSTextAlignmentRight;
    _durationLabel.textColor = VLCRedesignAppearance.mutedColor;
    _numberLabel = [self label];
    _numberLabel.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightMedium];
    _numberLabel.textColor = VLCRedesignAppearance.accentColor;
    _grip = [[NSImageView alloc] init];
    _grip.image = VLCQueueAsset(@"grip");
    _grip.imageScaling = NSImageScaleNone;
    [self addSubview:_durationLabel];
    [self addSubview:_numberLabel];
    [self addSubview:_grip];
    return self;
}

- (VLCRedesignAlignedLabel *)label
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:@""];
    label.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    label.textColor = VLCRedesignAppearance.subduedColor;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds), left = self.tab == 1 ? 4 : 46;
    CGFloat timeWidth = self.tab == 1 ? 104 : 74;
    self.textField.frame = NSMakeRect(left, 0, MAX(0, width - left - timeWidth - 10), 32);
    _durationLabel.frame = NSMakeRect(width - timeWidth - 4, 0, timeWidth, 32);
    _numberLabel.frame = NSMakeRect(4, 0, 34, 32);
    _grip.frame = NSMakeRect(4, 4, 24, 24);
    _grip.hidden = self.tab != 0;
    _numberLabel.hidden = self.tab != 2;
}

@end

@class VLCQueueBookmarkObserver;
@interface VLCRedesignQueuePanel () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
@property NSArray<VLCRedesignPanelButton *> *tabs;
@property NSView *header;
@property VLCRedesignAlignedLabel *counter;
@property VLCRedesignAlignedLabel *emptyLabel;
@property VLCRedesignPanelButton *sortButton;
@property VLCRedesignPanelButton *repeatButton;
@property VLCRedesignPanelButton *shuffleButton;
@property VLCRedesignPanelButton *removeButton;
@property VLCRedesignPanelButton *addButton;
@property NSScrollView *scroll;
@property NSTableView *table;
@property VLCPlayQueueDataSource *dragDataSource;
@property NSArray<VLCPlayQueueItem *> *items;
@property NSArray<VLCBookmark *> *bookmarks;
@property NSArray<NSDictionary *> *chapters;
@property VLCQueueBookmarkObserver *bookmarkObserver;
@property int64_t bookmarkMediaID;
@end
@interface VLCQueueBookmarkObserver : NSObject
@property (weak) VLCRedesignQueuePanel *owner;
@end
@implementation VLCQueueBookmarkObserver
@end

static void VLCQueueBookmarkChanged(void *data, const vlc_ml_event_t *event)
{
    if (event->i_type != VLC_ML_EVENT_BOOKMARKS_ADDED && event->i_type != VLC_ML_EVENT_BOOKMARKS_DELETED &&
        event->i_type != VLC_ML_EVENT_BOOKMARKS_UPDATED)
        return;
    __weak VLCRedesignQueuePanel *owner = ((__bridge VLCQueueBookmarkObserver *)data).owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (owner.selectedTab == 1)
            [owner refresh];
    });
}

@implementation VLCRedesignQueuePanel {
    vlc_medialibrary_t *_mediaLibrary;
    vlc_ml_event_callback_t *_bookmarkCallback;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (VLCPlayQueueController *)queue
{
    return VLCMain.sharedInstance.playQueueController;
}

- (VLCPlayerController *)player
{
    return self.queue.playerController;
}

- (void)updateAppearance
{
    self.layer.backgroundColor = VLCRedesignAppearance.overlayColor.CGColor;
    _header.layer.backgroundColor = VLCRedesignAppearance.recessedColor.CGColor;
    [VLCRedesignAppearance redisplay:self];
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = YES;
    _header = [[VLCQueueHeader alloc] init];
    _header.wantsLayer = YES;
    [self addSubview:_header];
    __weak typeof(self) weakSelf = self;
    NSMutableArray *tabs = [NSMutableArray array];
    NSArray *titles = @[ _NS("Queue"), _NS("Bookmarks"), _NS("Chapters") ];
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
    _counter = [VLCRedesignAlignedLabel labelWithString:@""];
    _counter.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    _counter.textColor = VLCRedesignAppearance.mutedColor;
    _counter.lineBreakMode = NSLineBreakByTruncatingTail;
    _counter.maximumNumberOfLines = 1;
    _counter.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:_counter];
    _sortButton = [self icon:@"sort"
                       label:_NS("Sort queue")
                      action:^{
                          [weakSelf sortMenu];
                      }];
    _repeatButton = [self icon:@"repeat"
                         label:_NS("Change repeat mode")
                        action:^{
                            VLCPlayQueueController *queue = weakSelf.queue;
                            queue.playbackRepeat = (queue.playbackRepeat + 1) % 3;
                        }];
    _repeatButton.highlightedSelection = YES;
    _shuffleButton = [self icon:@"shuffle"
                          label:_NS("Shuffle")
                         action:^{
                             VLCPlayQueueController *queue = weakSelf.queue;
                             queue.playbackOrder = queue.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL
                                                       ? VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM
                                                       : VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL;
                         }];
    _shuffleButton.highlightedSelection = YES;
    _removeButton = [self icon:@"remove"
                         label:_NS("Remove selected item")
                        action:^{
                            [weakSelf removeSelected:nil];
                        }];
    _addButton = [self icon:@"add"
                      label:_NS("Add media")
                     action:^{
                         [weakSelf add:nil];
                     }];
    _scroll = [[NSScrollView alloc] init];
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _table = [[VLCQueueTable alloc] init];
    _table.headerView = nil;
    ((VLCQueueTable *)_table).activateRow = ^{
        [weakSelf activateSelected:nil];
    };
    ((VLCQueueTable *)_table).removeRow = ^{
        [weakSelf removeSelected:nil];
    };
    if (@available(macOS 11.0, *))
        _table.style = NSTableViewStylePlain;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.autoresizingMask = NSViewWidthSizable;
    _scroll.automaticallyAdjustsContentInsets = NO;
    _scroll.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    _table.backgroundColor = NSColor.clearColor;
    _table.rowHeight = 44;
    _table.intercellSpacing = NSZeroSize;
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"item"];
    [_table addTableColumn:column];
    _table.delegate = self;
    _table.dataSource = self;
    _table.target = self;
    _table.doubleAction = @selector(activateSelected:);
    _scroll.documentView = _table;
    [self addSubview:_scroll];
    _emptyLabel = [VLCRedesignAlignedLabel labelWithString:@""];
    _emptyLabel.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    _emptyLabel.textColor = VLCRedesignAppearance.mutedColor;
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:_emptyLabel];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:_NS("Item actions")];
    menu.delegate = self;
    _table.menu = menu;
    _dragDataSource = [[VLCPlayQueueDataSource alloc] init];
    _dragDataSource.playQueueController = self.queue;
    _dragDataSource.tableView = _table;
    [_dragDataSource prepareForUse];
    [_table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    for (NSString *name in @[
             VLCPlayQueueItemsAdded, VLCPlayQueueItemsRemoved, VLCPlayQueueItemsUpdated,
             VLCPlayQueueCurrentItemIndexChanged, VLCPlaybackRepeatChanged, VLCPlaybackOrderChanged,
             VLCPlayerCurrentMediaItemChanged, VLCPlayerTitleListChanged, VLCPlayerTitleSelectionChanged,
             VLCPlayerChapterSelectionChanged
         ])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelChanged:) name:name object:nil];
    _mediaLibrary = vlc_ml_instance_get(getIntf());
    if (_mediaLibrary) {
        _bookmarkObserver = [[VLCQueueBookmarkObserver alloc] init];
        _bookmarkObserver.owner = self;
        _bookmarkCallback =
            vlc_ml_event_register_callback(_mediaLibrary, VLCQueueBookmarkChanged, (__bridge void *)_bookmarkObserver);
        // libvlc requires every library callback to be gone before it shuts down
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillTerminate:)
                                                   name:NSApplicationWillTerminateNotification
                                                 object:nil];
    }
    [self refresh];
    [self updateAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateAppearance)
                                               name:VLCRedesignAppearanceChanged
                                             object:nil];
    return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    if (_bookmarkCallback) {
        vlc_ml_event_unregister_callback(_mediaLibrary, _bookmarkCallback);
        _bookmarkCallback = NULL;
    }
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self applicationWillTerminate:nil];
}

- (VLCRedesignPanelButton *)icon:(NSString *)role label:(NSString *)label action:(void (^)(void))action
{
    VLCRedesignPanelButton *button = [[VLCRedesignPanelButton alloc] init];
    button.title = @"";
    button.image = VLCQueueAsset(role);
    button.toolTip = button.accessibilityLabel = label;
    button.activate = action;
    [self addSubview:button];
    return button;
}

- (void)setSelectedTab:(NSInteger)selectedTab
{
    if (selectedTab < 0 || selectedTab >= (NSInteger)_tabs.count || _selectedTab == selectedTab)
        return;
    _selectedTab = selectedTab;
    [_table deselectAll:nil];
    [self refresh];
    [_scroll.contentView scrollToPoint:NSZeroPoint];
}

- (void)modelChanged:(NSNotification *)notification
{
    if ([notification.name isEqualToString:VLCPlayerCurrentMediaItemChanged])
        [_table deselectAll:nil];
    [self refresh];
}

- (void)refresh
{
    uint64_t selectedID = 0;
    NSInteger selected = _table.selectedRow;
    BOOL hadQueueSelection = _selectedTab == 0 && selected >= 0 && selected < (NSInteger)_items.count;
    if (hadQueueSelection)
        selectedID = _items[selected].uniqueID;
    NSNumber *selectedBookmarkTime = _selectedTab == 1 && selected >= 0 && selected < (NSInteger)_bookmarks.count
                                         ? @(_bookmarks[selected].bookmarkTime)
                                         : nil;
    NSArray *roles = @[ @"queue", @"bookmarks", @"chapters" ];
    for (NSInteger i = 0; i < 3; i++) {
        BOOL active = i == _selectedTab;
        _tabs[i].state = active ? NSControlStateValueOn : NSControlStateValueOff;
        _tabs[i].image = VLCQueueAsset([roles[i] stringByAppendingString:active ? @"-on" : @"-off"]);
        _tabs[i].underlineImage =
            VLCRedesignPanelImage(active ? @"VLC-redesign-tracks-tab-line-video" : @"VLC-redesign-tracks-tab-line-off");
        _tabs[i].needsDisplay = YES;
    }
    _items = self.queue.playQueueModel.playQueueItems.copy;
    _bookmarks = @[];
    _chapters = @[];
    if (_selectedTab == 1 && _mediaLibrary) {
        _bookmarkMediaID = [VLCMediaLibraryMediaItem mediaItemForURL:self.player.URLOfCurrentMediaItem].libraryID;
        if (_bookmarkMediaID > 0) {
            vlc_ml_bookmark_list_t *list = vlc_ml_list_media_bookmarks(_mediaLibrary, NULL, _bookmarkMediaID);
            NSMutableArray *bookmarks = [NSMutableArray array];
            if (list) {
                for (size_t i = 0; i < list->i_nb_items; i++)
                    [bookmarks addObject:[VLCBookmark bookmarkWithVlcBookmark:list->p_items[i]]];
                vlc_ml_bookmark_list_release(list);
            }
            _bookmarks = [bookmarks sortedArrayUsingComparator:^NSComparisonResult(VLCBookmark *a, VLCBookmark *b) {
                return a.bookmarkTime < b.bookmarkTime   ? NSOrderedAscending
                       : a.bookmarkTime > b.bookmarkTime ? NSOrderedDescending
                                                         : NSOrderedSame;
            }];
        }
    } else if (_selectedTab == 2) {
        const struct vlc_player_title *title = self.player.selectedTitle;
        NSMutableArray *chapters = [NSMutableArray array];
        if (title)
            for (size_t i = 0; i < title->chapter_count; i++) {
                const struct vlc_player_chapter *chapter = &title->chapters[i];
                [chapters addObject:@{@"name" : toNSStr(chapter->name), @"time" : @(chapter->time)}];
            }
        _chapters = chapters;
    }
    if (_selectedTab == 0) {
        vlc_tick_t total = 0;
        BOOL known = YES;
        for (VLCPlayQueueItem *item in _items) {
            if (item.duration <= 0)
                known = NO;
            else
                total += item.duration;
        }
        NSString *duration = known ? VLCQueueTime(total, NO) : _NS("Unknown duration");
        _counter.stringValue = _items.count == 1
                                    ? [NSString stringWithFormat:_NS("1 item - %@"), duration]
                                    : [NSString stringWithFormat:_NS("%lu items - %@"), _items.count, duration];
    } else
        _counter.stringValue = [NSString stringWithFormat:_NS("%lu Bookmarks"), _bookmarks.count];
    _counter.hidden = _selectedTab == 2;
    _sortButton.hidden = _repeatButton.hidden = _shuffleButton.hidden = _selectedTab != 0;
    _removeButton.hidden = _addButton.hidden = _selectedTab == 2;
    _addButton.toolTip = _addButton.accessibilityLabel =
        _selectedTab == 1 ? _NS("Bookmark current time") : _NS("Add media to queue");
    _addButton.enabled = _selectedTab != 1 || (_mediaLibrary && self.player.currentMedia && self.player.seekable);
    _repeatButton.state =
        self.queue.playbackRepeat == VLC_PLAYLIST_PLAYBACK_REPEAT_NONE ? NSControlStateValueOff : NSControlStateValueOn;
    NSString *repeat = self.queue.playbackRepeat == VLC_PLAYLIST_PLAYBACK_REPEAT_ALL       ? _NS("Repeat all")
                       : self.queue.playbackRepeat == VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT ? _NS("Repeat current item")
                                                                                           : _NS("Repeat off");
    _repeatButton.toolTip = _repeatButton.accessibilityLabel = repeat;
    _shuffleButton.state =
        self.queue.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM ? NSControlStateValueOn : NSControlStateValueOff;
    _repeatButton.needsDisplay = _shuffleButton.needsDisplay = YES;
    [_table reloadData];
    if (hadQueueSelection) {
        NSUInteger index = [_items
            indexOfObjectPassingTest:^BOOL(VLCPlayQueueItem *item, NSUInteger __unused idx, BOOL *__unused stop) {
                return item.uniqueID == selectedID;
            }];
        if (index != NSNotFound)
            [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    }
    if (selectedBookmarkTime) {
        NSUInteger index = [_bookmarks
            indexOfObjectPassingTest:^BOOL(VLCBookmark *bookmark, NSUInteger __unused idx, BOOL *__unused stop) {
                return bookmark.bookmarkTime == selectedBookmarkTime.longLongValue;
            }];
        if (index != NSNotFound)
            [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    }
    if (_selectedTab == 2 && self.player.selectedChapterIndex < _chapters.count)
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:self.player.selectedChapterIndex]
            byExtendingSelection:NO];
    _removeButton.enabled = _table.selectedRow >= 0;
    NSInteger count = [self numberOfRowsInTableView:_table];
    _emptyLabel.hidden = count > 0;
    _emptyLabel.stringValue = _selectedTab == 0   ? _NS("Your queue is empty")
                              : _selectedTab == 1 ? _NS("No bookmarks yet")
                                                  : _NS("This media has no chapters");
    self.needsLayout = YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _selectedTab == 0 ? _items.count : _selectedTab == 1 ? _bookmarks.count : _chapters.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    VLCQueueCell *cell = [tableView makeViewWithIdentifier:@"redesign-item" owner:self];
    if (!cell) {
        cell = [[VLCQueueCell alloc] init];
        cell.identifier = @"redesign-item";
    }
    cell.tab = _selectedTab;
    NSString *title, *time;
    BOOL current = NO;
    if (_selectedTab == 0) {
        VLCPlayQueueItem *item = _items[row];
        title = item.title;
        time = VLCQueueTime(item.duration, NO);
        current = self.queue.currentPlayQueueIndex == (size_t)row;
    } else if (_selectedTab == 1) {
        VLCBookmark *bookmark = _bookmarks[row];
        title = bookmark.bookmarkName.length ? bookmark.bookmarkName : _NS("Bookmark");
        time = VLCQueueTime(VLC_TICK_FROM_MS(bookmark.bookmarkTime), YES);
    } else {
        title = _chapters[row][@"name"];
        time = VLCQueueTime([_chapters[row][@"time"] longLongValue], NO);
    }
    cell.textField.stringValue = title ?: @"";
    cell.textField.toolTip = title;
    cell.textField.textColor = current ? VLCRedesignAppearance.accentColor : VLCRedesignAppearance.subduedColor;
    cell.durationLabel.stringValue = time;
    cell.numberLabel.stringValue = [NSString stringWithFormat:@"%ld", row + 1];
    cell.needsLayout = YES;
    return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    return [[VLCQueueRow alloc] init];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    _removeButton.enabled = _table.selectedRow >= 0;
}

- (void)activateSelected:(id)sender
{
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= [self numberOfRowsInTableView:_table])
        return;
    if (_selectedTab == 0)
        [self.queue playItemAtIndex:row];
    else if (_selectedTab == 1)
        [self.player setTimePrecise:VLC_TICK_FROM_MS(_bookmarks[row].bookmarkTime)];
    else
        self.player.selectedChapterIndex = row;
}

- (void)removeSelected:(id)sender
{
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= [self numberOfRowsInTableView:_table])
        return;
    if (_selectedTab == 0)
        [self.queue removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:row]];
    else if (_selectedTab == 1) {
        vlc_ml_media_remove_bookmark(_mediaLibrary, _bookmarkMediaID, _bookmarks[row].bookmarkTime);
        [self refresh];
    }
}

- (void)add:(id)sender
{
    if (_selectedTab == 1) {
        if (!_mediaLibrary || !self.player.currentMedia || !self.player.seekable)
            return;
        if (_bookmarkMediaID <= 0) {
            VLCMediaLibraryMediaItem *item =
                [[VLCMediaLibraryMediaItem alloc] initWithExternalURL:self.player.URLOfCurrentMediaItem];
            _bookmarkMediaID = item.libraryID;
        }
        int64_t time = MS_FROM_VLC_TICK(MAX(0, self.player.time));
        if (_bookmarkMediaID <= 0 || vlc_ml_media_add_bookmark(_mediaLibrary, _bookmarkMediaID, time) != VLC_SUCCESS) {
            NSBeep();
            return;
        }
        NSString *name = [NSString stringWithFormat:_NS("Bookmark %@"), VLCQueueTime(VLC_TICK_FROM_MS(time), NO)];
        vlc_ml_media_update_bookmark(_mediaLibrary, _bookmarkMediaID, time, name.UTF8String, "");
        [self refresh];
        return;
    }
    NSOpenPanel *picker = NSOpenPanel.openPanel;
    picker.canChooseDirectories = YES;
    picker.allowsMultipleSelection = YES;
    [picker beginSheetModalForWindow:self.window
                   completionHandler:^(NSModalResponse response) {
                       if (response != NSModalResponseOK)
                           return;
                       NSMutableArray *items = [NSMutableArray array];
                       for (NSURL *url in picker.URLs)
                           [items addObject:[VLCOpenInputMetadata inputMetaWithPath:url.path]];
                       [self.queue addPlayQueueItems:items atPosition:(size_t)-1 startPlayback:NO];
                   }];
}

- (void)renameBookmark:(id)sender
{
    NSInteger row = _table.selectedRow;
    if (_selectedTab != 1 || row < 0 || row >= (NSInteger)_bookmarks.count)
        return;
    VLCBookmark *bookmark = _bookmarks[row];
    int64_t mediaID = _bookmarkMediaID;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Rename bookmark");
    [alert addButtonWithTitle:_NS("Save")];
    [alert addButtonWithTitle:_NS("Cancel")];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    field.stringValue = bookmark.bookmarkName;
    alert.accessoryView = field;
    [alert beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse response) {
                      if (response == NSAlertFirstButtonReturn && field.stringValue.length) {
                          vlc_ml_media_update_bookmark(self->_mediaLibrary, mediaID, bookmark.bookmarkTime,
                                                       field.stringValue.UTF8String,
                                                       bookmark.bookmarkDescription.UTF8String);
                          [self refresh];
                      }
                  }];
}

- (void)sortMenu
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:_NS("Sort queue")];
    NSArray *titles = @[ _NS("Title"), _NS("Duration"), _NS("Artist"), _NS("Album"), _NS("URL") ];
    int keys[] = {VLC_PLAYLIST_SORT_KEY_TITLE, VLC_PLAYLIST_SORT_KEY_DURATION, VLC_PLAYLIST_SORT_KEY_ARTIST,
                  VLC_PLAYLIST_SORT_KEY_ALBUM, VLC_PLAYLIST_SORT_KEY_URL};
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem *item = [menu addItemWithTitle:titles[i] action:@selector(sort:) keyEquivalent:@""];
        item.target = self;
        item.tag = keys[i];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 24) inView:_sortButton];
}

- (void)sort:(NSMenuItem *)sender
{
    enum vlc_playlist_sort_order order = !self.queue.unsorted && self.queue.lastSortKey == sender.tag &&
                                                 self.queue.lastSortOrder == VLC_PLAYLIST_SORT_ORDER_ASCENDING
                                             ? VLC_PLAYLIST_SORT_ORDER_DESCENDING
                                             : VLC_PLAYLIST_SORT_ORDER_ASCENDING;
    [self.queue sortByKey:(enum vlc_playlist_sort_key)sender.tag andOrder:order];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    NSInteger clicked = _table.clickedRow;
    if (clicked >= 0)
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:clicked] byExtendingSelection:NO];
    if (_table.selectedRow < 0)
        return;
    NSMenuItem *play = [menu addItemWithTitle:_selectedTab == 0 ? _NS("Play") : _NS("Go to time")
                                       action:@selector(activateSelected:)
                                keyEquivalent:@""];
    play.target = self;
    if (_selectedTab == 0) {
        NSMenuItem *earlier = [menu addItemWithTitle:_NS("Move earlier")
                                              action:@selector(moveEarlier:)
                                       keyEquivalent:@""];
        earlier.target = self;
        NSMenuItem *later = [menu addItemWithTitle:_NS("Move later") action:@selector(moveLater:) keyEquivalent:@""];
        later.target = self;
    }
    if (_selectedTab == 1) {
        NSMenuItem *rename = [menu addItemWithTitle:_NS("Rename…") action:@selector(renameBookmark:) keyEquivalent:@""];
        rename.target = self;
    }
    if (_selectedTab != 2) {
        NSMenuItem *remove = [menu addItemWithTitle:_NS("Remove") action:@selector(removeSelected:) keyEquivalent:@""];
        remove.target = self;
    }
}

- (void)moveEarlier:(id)sender
{
    [self moveSelectedBy:-1];
}

- (void)moveLater:(id)sender
{
    [self moveSelectedBy:1];
}

- (void)moveSelectedBy:(NSInteger)offset
{
    NSInteger row = _table.selectedRow, target = row + offset;
    if (_selectedTab != 0 || row < 0 || target < 0 || row >= (NSInteger)_items.count ||
        target >= (NSInteger)_items.count)
        return;
    [self.queue moveItemWithID:_items[row].uniqueID toPosition:target];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    return _selectedTab == 0 ? [_dragDataSource tableView:tableView pasteboardWriterForRow:row] : nil;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (_selectedTab != 0)
        return NSDragOperationNone;
    NSDragOperation validated = [_dragDataSource tableView:tableView
                                              validateDrop:info
                                               proposedRow:row
                                     proposedDropOperation:operation];
    return info.draggingSource == tableView && validated != NSDragOperationNone ? NSDragOperationMove : validated;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
    if (_selectedTab != 0)
        return NO;
    if ([info.draggingPasteboard availableTypeFromArray:@[
            VLCPlaylistItemPasteboardType, VLCMediaLibraryMediaItemPasteboardType, VLCMediaLibraryMediaItemUTI
        ]])
        return [_dragDataSource tableView:tableView acceptDrop:info row:row dropOperation:operation];
    NSArray<VLCOpenInputMetadata *> *metadata =
        [VLCFileDragRecognisingView inputMetadataFromPasteboard:info.draggingPasteboard];
    if (!metadata.count)
        return NO;
    size_t position = row < 0 ? NSUIntegerMax : MIN((size_t)row, self.queue.playQueueModel.numberOfPlayQueueItems);
    [self.queue addPlayQueueItems:metadata atPosition:position startPlayback:NO];
    return YES;
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds), tabWidth = (width - 14) / 3;
    _header.frame = NSMakeRect(0, 0, width, 50);
    for (NSUInteger i = 0; i < 3; i++)
        _tabs[i].frame = NSMakeRect(6 + i * (tabWidth + 1), 0, tabWidth, 50);
    CGFloat right = width - 20;
    for (VLCRedesignPanelButton *button in @[ _addButton, _removeButton, _shuffleButton, _repeatButton, _sortButton ]) {
        button.frame = NSMakeRect(right - 24, 70, 24, 28);
        right -= 36;
    }
    _counter.frame = NSMakeRect(28, 70, MAX(0, (_selectedTab == 0 ? right : width - 100) - 28), 28);
    CGFloat top = _selectedTab == 2 ? 70 : 118;
    _scroll.frame = NSMakeRect(20, top, MAX(0, width - 40), MAX(0, height - top - 20));
    [_scroll tile];
    CGFloat tableWidth = NSWidth(_scroll.contentView.bounds);
    _table.frame = NSMakeRect(0, 0, tableWidth, MAX(NSHeight(_scroll.contentView.bounds), _table.numberOfRows * 44));
    _table.tableColumns.firstObject.width = tableWidth;
    _emptyLabel.frame = NSMakeRect(28, top + 12, MAX(0, width - 56), 60);
}

@end
