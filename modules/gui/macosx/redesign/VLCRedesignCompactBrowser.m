/*****************************************************************************
 * VLCRedesignCompactBrowser.m: Compact media library beside the video
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import "VLCRedesignCompactBrowser.h"
#import "VLCRedesignPanelButton.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSPasteboardItem+VLCAdditions.h"
#import "main/VLCMain.h"
#import "menus/VLCMainMenu.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/media-source/VLCMediaSource.h"
#import "library/media-source/VLCMediaSourceProvider.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "views/VLCFileDragRecognisingView.h"
#import "windows/VLCOpenInputMetadata.h"
#import "windows/VLCOpenWindowController.h"
#import <vlc_interface.h>
#import <fcntl.h>
#import <unistd.h>

static NSImage *VLCBrowserAsset(NSString *role)
{
    return VLCRedesignPanelImage([@"VLC-redesign-browser-" stringByAppendingString:role]);
}
static VLCRedesignAlignedLabel *VLCBrowserLabel(CGFloat size, NSUInteger color)
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:@""];
    label.font = [VLCRedesignAppearance fontOfSize:size weight:NSFontWeightRegular];
    label.textColor = [VLCRedesignAppearance colorWithRGB:color];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}
static void VLCBrowserDrawGridIcon(NSRect rect)
{
    [[VLCRedesignAppearance colorWithRGB:0x8F8F8F] setStroke];
    for (NSUInteger row=0;row<2;row++) for (NSUInteger column=0;column<2;column++) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(rect.origin.x+1+column*12,rect.origin.y+3+row*10,10,8) xRadius:2 yRadius:2];
        path.lineWidth = 1.5; [path stroke];
    }
}
@interface VLCBrowserIconButton : VLCRedesignPanelButton
@property BOOL mirrorIcon;
@end
@implementation VLCBrowserIconButton
- (void)drawRect:(NSRect)dirtyRect
{
    [NSGraphicsContext saveGraphicsState];
    if (self.mirrorIcon) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:NSWidth(self.bounds) yBy:0]; [transform scaleXBy:-1 yBy:1]; [transform concat];
    }
    [super drawRect:dirtyRect];
    [NSGraphicsContext restoreGraphicsState];
}
@end
@interface VLCBrowserModeButton : VLCRedesignPanelButton
@property BOOL gridIcon;
@end
@implementation VLCBrowserModeButton
- (void)drawRect:(NSRect)dirtyRect
{
    if (!self.gridIcon) { [super drawRect:dirtyRect]; return; }
    if (self.highlighted) { [[VLCRedesignAppearance colorWithRGB:0x222222] setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill]; }
    VLCBrowserDrawGridIcon(NSMakeRect(NSMidX(self.bounds)-12,NSMidY(self.bounds)-12,24,24));
    if (self.window.firstResponder == self) { [VLCRedesignAppearance.accentColor setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:4 yRadius:4] stroke]; }
}
@end
@interface VLCBrowserAddressButton : NSButton
@end
@implementation VLCBrowserAddressButton
- (void)drawRect:(NSRect)dirtyRect
{
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init]; style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:self.title attributes:@{NSFontAttributeName:[VLCRedesignAppearance fontOfSize:16 weight:NSFontWeightRegular],NSForegroundColorAttributeName:[VLCRedesignAppearance colorWithRGB:0x8F8F8F],NSParagraphStyleAttributeName:style}];
    VLCDrawAlignedText(text,self.bounds,self.flipped,NSTextAlignmentLeft);
    if (self.window.firstResponder == self) { [VLCRedesignAppearance.accentColor setStroke]; [NSBezierPath strokeRect:NSInsetRect(self.bounds,1,1)]; }
}
@end
@interface VLCBrowserSurface : NSView
@end
@implementation VLCBrowserSurface
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
@end

/* SVGs keep their intrinsic size; media thumbnails alone fill/crop their slot. */
@interface VLCBrowserArtwork : NSImageView
@property BOOL intrinsicAsset;
@property BOOL mirrorIcon;
@property CGFloat progress;
@end
@implementation VLCBrowserArtwork
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)drawRect:(NSRect)dirtyRect
{
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:2 yRadius:2] addClip];
    if (!self.intrinsicAsset) { [[VLCRedesignAppearance colorWithRGB:0x303030] setFill]; NSRectFill(self.bounds); }
    NSSize size = self.image.size;
    if (size.width > 0 && size.height > 0) {
        CGFloat scale = self.intrinsicAsset ? 1 : MAX(NSWidth(self.bounds)/size.width,NSHeight(self.bounds)/size.height);
        NSRect rect = NSMakeRect(NSMidX(self.bounds)-size.width*scale/2,NSMidY(self.bounds)-size.height*scale/2,size.width*scale,size.height*scale);
        if (self.mirrorIcon) {
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:NSWidth(self.bounds) yBy:0]; [transform scaleXBy:-1 yBy:1]; [transform concat];
        }
        [self.image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    }
    if (self.progress > 0) {
        [[VLCRedesignAppearance colorWithRGB:0xD37918] setFill];
        NSRectFill(NSMakeRect(0,self.flipped ? NSHeight(self.bounds)-3 : 0,MAX(0,MIN(1,self.progress))*NSWidth(self.bounds),3));
    }
    [NSGraphicsContext restoreGraphicsState];
}
@end
@interface VLCBrowserCell : NSTableCellView
@property VLCBrowserArtwork *artwork;
@property NSURL *representedURL;
@end
@implementation VLCBrowserCell
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (self) { self.textField = VLCBrowserLabel(14,0x8F8F8F); _artwork = [[VLCBrowserArtwork alloc] init]; [self addSubview:_artwork]; [self addSubview:self.textField]; }
    return self;
}
- (void)layout
{
    [super layout]; _artwork.frame = NSMakeRect(0,0,32,32);
    self.textField.frame = NSMakeRect(42,0,MAX(0,NSWidth(self.bounds)-42),32);
}
@end
@interface VLCBrowserTable : NSTableView
@property (copy) void (^activateRow)(void);
@end
@implementation VLCBrowserTable
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) { if (self.activateRow) self.activateRow(); }
    else [super keyDown:event];
}
@end
@interface VLCBrowserRow : NSTableRowView
@end
@implementation VLCBrowserRow
- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    [[VLCRedesignAppearance colorWithRGB:0x371F06] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
}
@end
@interface VLCBrowserGridItem : NSCollectionViewItem
@property VLCBrowserArtwork *artwork;
@property NSURL *representedURL;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserGridItem
- (void)loadView
{
    self.view = [[VLCBrowserSurface alloc] init];
    _artwork = [[VLCBrowserArtwork alloc] init];
    NSTextField *caption = VLCBrowserLabel(16,0x969696);
    [self.view addSubview:caption]; self.textField = caption;
    self.textField.maximumNumberOfLines = 1; self.textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:_artwork];
    _artwork.translatesAutoresizingMaskIntoConstraints = self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_artwork.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [_artwork.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_artwork.topAnchor constraintEqualToAnchor:self.view.topAnchor], [_artwork.heightAnchor constraintEqualToAnchor:_artwork.widthAnchor multiplier:9./16.],
        [self.textField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.textField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textField.topAnchor constraintEqualToAnchor:_artwork.bottomAnchor constant:8], [self.textField.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    NSClickGestureRecognizer *gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(open:)];
    gesture.numberOfClicksRequired = 2; gesture.delaysPrimaryMouseButtonEvents = NO; [self.view addGestureRecognizer:gesture];
}
- (void)open:(id)sender { if (self.activate) self.activate(); }
- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected]; self.view.wantsLayer = YES;
    self.view.layer.borderWidth = selected ? 2 : 0; self.view.layer.cornerRadius = 4;
    self.view.layer.borderColor = VLCRedesignAppearance.accentColor.CGColor;
}
@end
@interface VLCBrowserGrid : NSCollectionView
@property (copy) void (^activateItem)(void);
@end
@implementation VLCBrowserGrid
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) { if (self.activateItem) self.activateItem(); }
    else [super keyDown:event];
}
@end

@interface VLCBrowserViewOption : NSButton
@property BOOL gridIcon;
@property BOOL chosen;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserViewOption
- (BOOL)isFlipped { return YES; }
- (instancetype)init { self = [super init]; if (self) { self.bordered = NO; self.target = self; self.action = @selector(invoke:); } return self; }
- (void)invoke:(id)sender { if (self.activate) self.activate(); }
- (void)drawRect:(NSRect)dirtyRect
{
    if (self.chosen || self.highlighted) {
        [[VLCRedesignAppearance colorWithRGB:0x1F1F1F] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    }
    NSRect icon = NSMakeRect(14,12,24,24);
    if (self.gridIcon) {
        VLCBrowserDrawGridIcon(icon);
    } else [VLCBrowserAsset(@"list-view") drawInRect:icon fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:self.title attributes:@{NSFontAttributeName:[VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular],NSForegroundColorAttributeName:[VLCRedesignAppearance colorWithRGB:0x8F8F8F]}];
    VLCDrawAlignedText(text,NSMakeRect(48,0,MAX(0,NSWidth(self.bounds)-100),48),YES,NSTextAlignmentLeft);
    if (self.chosen) [VLCRedesignPanelImage(@"VLC-redesign-tracks-check") drawInRect:NSMakeRect(NSWidth(self.bounds)-38,12,24,24) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}
@end
@interface VLCBrowserPopup : NSPanel
@end
@implementation VLCBrowserPopup
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface VLCRedesignCompactBrowser () <NSTableViewDataSource,NSTableViewDelegate,NSCollectionViewDataSource,NSCollectionViewDelegate,NSMenuDelegate,NSTextFieldDelegate>
@property NSView *rail;
@property NSArray<VLCRedesignPanelButton *> *railButtons;
@property VLCRedesignPanelButton *backButton;
@property VLCRedesignPanelButton *forwardButton;
@property VLCRedesignPanelButton *moreButton;
@property VLCRedesignPanelButton *expandButton;
@property VLCRedesignPanelButton *sortButton;
@property VLCRedesignPanelButton *viewButton;
@property VLCRedesignPanelButton *searchButton;
@property VLCBrowserAddressButton *address;
@property VLCRedesignAlignedLabel *counter;
@property VLCRedesignAlignedLabel *message;
@property NSTextField *searchField;
@property NSImageView *divider;
@property NSScrollView *scroll;
@property VLCBrowserTable *table;
@property VLCBrowserGrid *grid;
@property NSCollectionViewFlowLayout *gridLayout;
@property NSArray<NSDictionary *> *rawEntries;
@property NSArray<NSDictionary *> *entries;
@property NSMutableArray<NSDictionary *> *history;
@property NSInteger historyIndex;
@property (atomic) NSUInteger generation;
@property dispatch_queue_t loadQueue;
@property dispatch_source_t directoryWatch;
@property NSCache<NSString *, NSImage *> *artworkCache;
@property NSMutableDictionary<NSString *, NSMutableArray *> *pendingArtwork;
@property NSInteger sortMode;
@property BOOL gridMode;
@property BOOL searchOpen;
@property NSString *loadError;
@property VLCBrowserPopup *viewPopup;
@property id popupMonitor;
@end
@implementation VLCRedesignCompactBrowser
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (VLCPlayQueueController *)queue { return VLCMain.sharedInstance.playQueueController; }
- (VLCLibraryModel *)model { return VLCMain.sharedInstance.libraryController.libraryModel; }
- (NSDictionary *)state { return _history[_historyIndex]; }
- (NSURL *)currentFolderURL { return self.state[@"url"]; }
- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect]; if (!self) return nil;
    self.wantsLayer = YES; self.layer.backgroundColor = [[VLCRedesignAppearance colorWithRGB:0x0E0E0E] colorWithAlphaComponent:.95].CGColor;
    _rail = [[VLCBrowserSurface alloc] init]; _rail.wantsLayer = YES; _rail.layer.backgroundColor = [VLCRedesignAppearance colorWithRGB:0x191919].CGColor; [self addSubview:_rail];
    __weak typeof(self) weakSelf = self;
    NSArray *roles = @[@"home",@"videos",@"music",@"network",@"playlists",@"recent",@"add"];
    NSArray *names = @[_NS("Home"),_NS("Videos"),_NS("Music"),_NS("Network"),_NS("Playlists"),_NS("Recent files"),_NS("Open media")];
    NSMutableArray *rail = [NSMutableArray array];
    for (NSInteger i=0;i<7;i++) { VLCRedesignPanelButton *button = [self icon:roles[i] label:names[i] parent:_rail action:^{ [weakSelf selectSection:i]; }]; [rail addObject:button]; }
    _railButtons = rail;
    _backButton = [self icon:@"back" label:_NS("Back") parent:self action:^{ [weakSelf moveHistory:-1]; }];
    _forwardButton = [self icon:@"forward" label:_NS("Forward") parent:self action:^{ [weakSelf moveHistory:1]; }];
    _moreButton = [self icon:@"more" label:_NS("Browser actions") parent:self action:^{ [weakSelf showActions]; }];
    _expandButton = [self icon:@"expand" label:_NS("Open full library") parent:self action:^{ [weakSelf expand]; }];
    _sortButton = [self icon:@"sort" label:_NS("Sort media") parent:self action:^{ [weakSelf showSort]; }];
    _viewButton = [[VLCBrowserModeButton alloc] init]; _viewButton.title = @""; _viewButton.image = VLCBrowserAsset(@"view"); _viewButton.toolTip = _viewButton.accessibilityLabel = _NS("View options"); _viewButton.activate = ^{ [weakSelf showViewOptions]; }; [self addSubview:_viewButton];
    _searchButton = [self icon:@"search" label:_NS("Search media") parent:self action:^{ [weakSelf toggleSearch]; }];
    _address = [[VLCBrowserAddressButton alloc] init]; _address.title = @""; _address.bordered = NO; _address.target = self; _address.action = @selector(showParents:);
    _counter = VLCBrowserLabel(14,0x6B6B6B); _message = VLCBrowserLabel(14,0x6B6B6B);
    _message.maximumNumberOfLines = 0; _message.lineBreakMode = NSLineBreakByWordWrapping;
    [self addSubview:_address]; [self addSubview:_counter]; [self addSubview:_message];
    _address.toolTip = _NS("Browse parent folders");
    _divider = [[NSImageView alloc] init]; _divider.image = VLCBrowserAsset(@"divider"); _divider.imageScaling = NSImageScaleNone; [self addSubview:_divider];
    _searchField = [[NSTextField alloc] init]; _searchField.cell = [[VLCRedesignAlignedTextFieldCell alloc] initTextCell:@""];
    _searchField.editable = YES; _searchField.selectable = YES; _searchField.usesSingleLineMode = YES;
    _searchField.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular]; _searchField.textColor = [VLCRedesignAppearance colorWithRGB:0x8F8F8F];
    _searchField.backgroundColor = [VLCRedesignAppearance colorWithRGB:0x090909]; _searchField.drawsBackground = YES; _searchField.bordered = NO;
    _searchField.placeholderString = _NS("Search media"); _searchField.accessibilityLabel = _NS("Search media"); _searchField.delegate = self;
    _searchField.hidden = YES; _searchField.wantsLayer = YES; _searchField.layer.cornerRadius = 4; _searchField.layer.masksToBounds = YES; [self addSubview:_searchField];
    _scroll = [[NSScrollView alloc] init]; _scroll.drawsBackground = NO; _scroll.hasVerticalScroller = YES; _scroll.autohidesScrollers = YES;
    _scroll.automaticallyAdjustsContentInsets = NO; _scroll.contentInsets = NSEdgeInsetsMake(0,0,0,0); [self addSubview:_scroll];
    _table = [[VLCBrowserTable alloc] init]; _table.backgroundColor = NSColor.clearColor; _table.headerView = nil; _table.rowHeight = 42; _table.intercellSpacing = NSZeroSize;
    if (@available(macOS 11.0,*)) _table.style = NSTableViewStylePlain;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle; _table.autoresizingMask = NSViewWidthSizable;
    [_table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"media"]]; _table.dataSource = self; _table.delegate = self; _table.target = self; _table.doubleAction = @selector(activateSelected:);
    _table.activateRow = ^{ [weakSelf activateSelected:nil]; };
    _grid = [[VLCBrowserGrid alloc] init]; _grid.backgroundColors = @[NSColor.clearColor]; _grid.selectable = YES; _grid.dataSource = self; _grid.delegate = self;
    _gridLayout = [[NSCollectionViewFlowLayout alloc] init]; _gridLayout.minimumInteritemSpacing = _gridLayout.minimumLineSpacing = 10; _grid.collectionViewLayout = _gridLayout;
    [_grid registerClass:VLCBrowserGridItem.class forItemWithIdentifier:@"media"];
    _grid.activateItem = ^{ [weakSelf activateSelected:nil]; };
    NSArray *dragTypes = @[NSPasteboardTypeFileURL,NSPasteboardTypeURL,NSPasteboardTypeString,NSFilenamesPboardType,VLCMediaLibraryMediaItemUTI,VLCMediaLibraryMediaItemPasteboardType];
    [_table registerForDraggedTypes:dragTypes]; [_grid registerForDraggedTypes:dragTypes];
    [_table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES]; [_grid setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    NSMenu *menu = [[NSMenu alloc] init]; menu.delegate = self; _table.menu = _grid.menu = menu;
    _history = [NSMutableArray arrayWithObject:@{@"section":@1,@"mode":@"folders",@"name":_NS("Videos")}];
    _loadQueue = dispatch_queue_create("org.videolan.redesign.browser",DISPATCH_QUEUE_SERIAL);
    _artworkCache = [[NSCache alloc] init]; _artworkCache.countLimit = 128; _artworkCache.totalCostLimit = 16*1024*1024; _pendingArtwork = [NSMutableDictionary dictionary];
    _gridMode = [NSUserDefaults.standardUserDefaults boolForKey:@"VLCRedesignCompactGrid"];
    _scroll.documentView = _gridMode ? _grid : _table;
    for (NSString *name in @[VLCLibraryModelListOfMonitoredFoldersUpdated,VLCLibraryModelAudioMediaListReset,VLCLibraryModelRecentsMediaListReset,VLCLibraryModelArtistListReset,VLCLibraryModelAlbumListReset,VLCLibraryModelGenreListReset,VLCLibraryModelPlaylistAdded,VLCLibraryModelPlaylistUpdated,VLCLibraryModelPlaylistDeleted,VLCLibraryModelDiscoveryCompleted])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelChanged:) name:name object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(progressChanged:) name:VLCPlayerTimeAndPositionChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(closePopupNotification:) name:NSApplicationDidResignActiveNotification object:nil];
    [self reload]; return self;
}
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_directoryWatch) dispatch_source_cancel(_directoryWatch);
    if (_popupMonitor) [NSEvent removeMonitor:_popupMonitor];
    [_viewPopup.parentWindow removeChildWindow:_viewPopup]; [_viewPopup orderOut:nil];
}
- (void)setHidden:(BOOL)hidden
{
    [super setHidden:hidden];
    if (hidden) { [self closePopup]; if (_directoryWatch) { dispatch_source_cancel(_directoryWatch); _directoryWatch = nil; } }
    else if (_history) [self reload];
}
- (void)viewWillMoveToWindow:(NSWindow *)window { if (!window) [self closePopup]; [super viewWillMoveToWindow:window]; }
- (VLCRedesignPanelButton *)icon:(NSString *)role label:(NSString *)label parent:(NSView *)parent action:(void (^)(void))action
{
    VLCBrowserIconButton *button = [[VLCBrowserIconButton alloc] init];
    button.mirrorIcon = [@[@"home",@"videos",@"network",@"recent",@"back",@"forward"] containsObject:role];
    button.title = @""; button.image = VLCBrowserAsset(role); button.toolTip = button.accessibilityLabel = label; button.activate = action; [parent addSubview:button]; return button;
}
- (void)navigate:(NSDictionary *)state
{
    [self closePopup];
    if (_historyIndex+1 < (NSInteger)_history.count) [_history removeObjectsInRange:NSMakeRange(_historyIndex+1,_history.count-_historyIndex-1)];
    [_history addObject:state];
    if (_history.count > 64) [_history removeObjectAtIndex:0];
    _historyIndex = _history.count-1; _searchField.stringValue = @"";
    _rawEntries = _entries = @[]; [_table reloadData]; [_grid reloadData];
    [_table deselectAll:nil]; _grid.selectionIndexPaths = [NSSet set]; [_scroll.contentView scrollToPoint:NSZeroPoint]; [self reload];
}
- (void)browseFolder:(NSURL *)url
{
    if (url.isFileURL) [self navigate:@{@"section":@1,@"mode":@"directory",@"name":url.lastPathComponent.length ? url.lastPathComponent : @"/",@"url":url}];
}
- (void)selectSection:(NSInteger)section
{
    if (section == 0) { if (self.expandLibrary) self.expandLibrary(nil,0,_gridMode); return; }
    if (section == 6) { [self addMedia:nil]; return; }
    NSArray *modes = @[@"",@"folders",@"music",@"network",@"playlists",@"recent"];
    NSArray *names = @[@"",_NS("Videos"),_NS("Music"),_NS("Network"),_NS("Playlists"),_NS("Recent files")];
    [self navigate:@{@"section":@(section),@"mode":modes[section],@"name":names[section]}];
}
- (void)moveHistory:(NSInteger)offset
{
    NSInteger next = _historyIndex+offset; if (next < 0 || next >= (NSInteger)_history.count) return;
    _historyIndex = next; _searchField.stringValue = @""; _rawEntries = _entries = @[]; [_table reloadData]; [_grid reloadData]; [_table deselectAll:nil]; _grid.selectionIndexPaths = [NSSet set]; [self reload];
}
- (NSDictionary *)entryForURL:(NSURL *)url directory:(BOOL)directory
{
    NSDictionary *values = [url resourceValuesForKeys:@[NSURLLocalizedNameKey,NSURLContentModificationDateKey] error:nil];
    NSMutableDictionary *entry = [@{@"kind":directory ? @"folder" : @"media",@"name":values[NSURLLocalizedNameKey] ?: url.lastPathComponent ?: url.absoluteString,@"url":url,@"modified":values[NSURLContentModificationDateKey] ?: NSDate.distantPast} mutableCopy];
    if (!directory) {
        VLCMediaLibraryMediaItem *media = [VLCMediaLibraryMediaItem mediaItemForURL:url];
        if (media) { entry[@"played"] = @(media.playCount); entry[@"progress"] = @(media.progress); }
    }
    return entry;
}
- (NSDictionary *)entryForLibraryItem:(id<VLCMediaLibraryItemProtocol>)item kind:(NSString *)kind
{
    NSMutableDictionary *entry = [@{@"kind":kind,@"name":item.displayString ?: @"",@"item":item} mutableCopy];
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        VLCMediaLibraryMediaItem *media = (VLCMediaLibraryMediaItem *)item;
        NSURL *url = [NSURL URLWithString:media.inputItem.MRL]; if (url) entry[@"url"] = url;
        entry[@"played"] = @(media.playCount); entry[@"progress"] = @(media.progress);
        if (url.isFileURL) {
            NSDate *modified; [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
            if (modified) entry[@"modified"] = modified;
        }
    }
    return entry;
}
- (void)modelChanged:(NSNotification *)notification
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!weakSelf.hidden) [weakSelf reload]; });
}
- (void)reload
{
    if (!_history) return;
    if (_directoryWatch) { dispatch_source_cancel(_directoryWatch); _directoryWatch = nil; }
    NSDictionary *state = self.state; NSString *mode = state[@"mode"]; NSInteger section = [state[@"section"] integerValue];
    _address.title = state[@"name"] ?: @""; _address.toolTip = self.currentFolderURL.path ?: _NS("Browse parent folders");
    _backButton.enabled = _historyIndex > 0; _forwardButton.enabled = _historyIndex+1 < (NSInteger)_history.count;
    NSArray *roles = @[@"home",@"videos",@"music",@"network",@"playlists",@"recent",@"add"];
    for (NSInteger i=0;i<7;i++) { NSString *role = roles[i]; if (i == section && i >= 1 && i <= 4 && ![mode isEqualToString:@"directory"]) role = [role stringByAppendingString:@"-active"]; _railButtons[i].image = VLCBrowserAsset(role);
        ((VLCBrowserIconButton *)_railButtons[i]).mirrorIcon = [@[@"home",@"videos",@"network",@"recent"] containsObject:role];
        _railButtons[i].needsDisplay = YES; }
    if (self.folderChanged) self.folderChanged(self.currentFolderURL);
    _counter.stringValue = _NS("Loading…"); _message.hidden = YES; _loadError = nil;
    NSUInteger generation = ++self.generation;
    /* Snapshot cached library lists on the main thread. Filesystem work and
     * sorting stay on a serial background queue, with stale loads discarded. */
    NSArray *snapshot = nil;
    if ([mode isEqualToString:@"folders"]) snapshot = self.model.listOfMonitoredFolders.copy;
    else if ([mode isEqualToString:@"songs"]) snapshot = self.model.listOfAudioMedia.copy;
    else if ([mode isEqualToString:@"albums"]) snapshot = self.model.listOfAlbums.copy;
    else if ([mode isEqualToString:@"artists"]) snapshot = self.model.listOfArtists.copy;
    else if ([mode isEqualToString:@"genres"]) snapshot = self.model.listOfGenres.copy;
    else if ([mode isEqualToString:@"playlists"]) snapshot = [self.model listOfPlaylistsOfType:VLC_ML_PLAYLIST_TYPE_ALL].copy;
    else if ([mode isEqualToString:@"recent"]) snapshot = self.model.listOfRecentMedia.copy;
    else if ([mode isEqualToString:@"group"]) snapshot = ((id<VLCMediaLibraryItemProtocol>)state[@"item"]).mediaItems.copy;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_loadQueue, ^{
        typeof(self) browser = weakSelf; if (!browser || browser.generation != generation) return;
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array]; NSError *error = nil;
        if ([mode isEqualToString:@"directory"]) {
            NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:state[@"url"] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLLocalizedNameKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
            NSSet *extensions = [NSSet setWithArray:[NSString extensionsArrayFromVLCStyleString:EXTENSIONS_MEDIA]];
            for (NSURL *url in children) {
                if (browser.generation != generation) return;
                NSNumber *directory; [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
                if (directory.boolValue || [extensions containsObject:url.pathExtension.lowercaseString]) [rows addObject:[browser entryForURL:url directory:directory.boolValue]];
            }
        } else if ([mode isEqualToString:@"folders"]) {
            for (VLCMediaLibraryEntryPoint *folder in snapshot) { NSURL *url = [NSURL URLWithString:folder.MRL]; if (url.isFileURL && !folder.isBanned) [rows addObject:[browser entryForURL:url directory:YES]]; }
        } else if ([mode isEqualToString:@"music"]) {
            NSArray *keys = @[@"songs",@"albums",@"artists",@"genres"], *names = @[_NS("Songs"),_NS("Albums"),_NS("Artists"),_NS("Genres")];
            for (NSUInteger i=0;i<keys.count;i++) [rows addObject:@{@"kind":@"category",@"mode":keys[i],@"name":names[i],@"icon":keys[i]}];
        } else if ([mode isEqualToString:@"network"]) {
            for (VLCMediaSource *source in [VLCMediaSourceProvider listOfMediaSourcesForCategory:SD_CAT_INTERNET])
                [rows addObject:@{@"kind":@"source",@"name":source.mediaSourceDescription ?: @"",@"source":source,@"icon":@"network"}];
        } else {
            BOOL groups = [@[@"albums",@"artists",@"genres"] containsObject:mode];
            for (id<VLCMediaLibraryItemProtocol> item in snapshot) {
                if (browser.generation != generation) return;
                NSMutableDictionary *entry = [[browser entryForLibraryItem:item kind:[mode isEqualToString:@"playlists"] ? @"playlist" : groups ? @"group" : @"media"] mutableCopy];
                if (groups) entry[@"icon"] = mode;
                [rows addObject:entry];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf; if (!strongSelf || strongSelf.generation != generation) return;
            strongSelf.rawEntries = rows; strongSelf.loadError = error.localizedDescription;
            [strongSelf applyFilter]; if ([mode isEqualToString:@"directory"] && !strongSelf.hidden) [strongSelf watchFolder:state[@"url"]];
        });
    });
}
- (void)watchFolder:(NSURL *)url
{
    int descriptor = open(url.fileSystemRepresentation,O_EVTONLY|O_CLOEXEC); if (descriptor < 0) return;
    _directoryWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,descriptor,DISPATCH_VNODE_WRITE|DISPATCH_VNODE_DELETE|DISPATCH_VNODE_RENAME|DISPATCH_VNODE_ATTRIB,_loadQueue);
    if (!_directoryWatch) { close(descriptor); return; }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_directoryWatch, ^{ dispatch_async(dispatch_get_main_queue(), ^{ if (!weakSelf.hidden) [weakSelf reload]; }); });
    dispatch_source_set_cancel_handler(_directoryWatch, ^{ close(descriptor); }); dispatch_resume(_directoryWatch);
}
- (void)applyFilter
{
    NSString *query = _searchField.stringValue;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in _rawEntries) if (!query.length || [entry[@"name"] localizedStandardContainsString:query]) [rows addObject:entry];
    NSInteger sortMode = _sortMode;
    NSString *mode = self.state[@"mode"];
    _sortButton.enabled = ![mode isEqualToString:@"music"];
    if (![mode isEqualToString:@"music"]) [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        if ([a[@"kind"] isEqualToString:@"folder"] != [b[@"kind"] isEqualToString:@"folder"]) return [a[@"kind"] isEqualToString:@"folder"] ? NSOrderedAscending : NSOrderedDescending;
        if (sortMode == 2) { NSComparisonResult result = [(b[@"modified"] ?: NSDate.distantPast) compare:(a[@"modified"] ?: NSDate.distantPast)]; if (result != NSOrderedSame) return result; }
        if (sortMode == 3 || sortMode == 4) { NSInteger playedA = [a[@"played"] integerValue] > 0, playedB = [b[@"played"] integerValue] > 0; if (playedA != playedB) return (playedA < playedB) == (sortMode == 3) ? NSOrderedAscending : NSOrderedDescending; }
        NSComparisonResult result = [a[@"name"] localizedStandardCompare:b[@"name"]]; return sortMode == 1 ? -result : result;
    }];
    _counter.stringValue = rows.count == 1 ? _NS("1 item") : [NSString stringWithFormat:_NS("%lu items"),rows.count];
    BOOL canAdd = [@[@"folders",@"music",@"network",@"playlists"] containsObject:mode];
    if (canAdd && !query.length) [rows insertObject:@{@"kind":@"add",@"name":[mode isEqualToString:@"network"] ? _NS("Add Network Stream") : [mode isEqualToString:@"playlists"] ? _NS("Create playlist") : _NS("Add"),@"icon":@"add"} atIndex:0];
    _entries = rows; [_table reloadData]; [_grid reloadData];
    ((VLCBrowserModeButton *)_viewButton).gridIcon = _gridMode; _viewButton.needsDisplay = YES;
    _message.hidden = rows.count > (canAdd && !query.length ? 1 : 0) || (!query.length && canAdd);
    _message.stringValue = _loadError ?: (query.length ? _NS("No matching media") : _NS("No media here yet"));
    if (_loadError.length) _message.hidden = NO;
    self.needsLayout = YES;
}
- (void)controlTextDidChange:(NSNotification *)notification { [self applyFilter]; }
- (void)toggleSearch
{
    [self closePopup]; _searchOpen = !_searchOpen; _searchField.hidden = !_searchOpen;
    _counter.hidden = _sortButton.hidden = _viewButton.hidden = _searchOpen;
    if (_searchOpen) [self.window makeFirstResponder:_searchField]; else { _searchField.stringValue = @""; [self applyFilter]; }
    self.needsLayout = YES;
}
- (NSInteger)selectedIndex
{
    return _gridMode ? (_grid.selectionIndexPaths.anyObject ? _grid.selectionIndexPaths.anyObject.item : -1) : _table.selectedRow;
}
- (void)activateSelected:(id)sender
{
    NSInteger index = self.selectedIndex; if (index >= 0 && index < (NSInteger)_entries.count) [self activateEntry:_entries[index]];
}
- (void)activateEntry:(NSDictionary *)entry
{
    NSString *kind = entry[@"kind"];
    if ([kind isEqualToString:@"add"]) [self addMedia:nil];
    else if ([kind isEqualToString:@"folder"]) [self browseFolder:entry[@"url"]];
    else if ([kind isEqualToString:@"category"]) [self navigate:@{@"section":@2,@"mode":entry[@"mode"],@"name":entry[@"name"]}];
    else if ([kind isEqualToString:@"group"] || [kind isEqualToString:@"playlist"]) [self navigate:@{@"section":self.state[@"section"],@"mode":@"group",@"name":entry[@"name"],@"item":entry[@"item"]}];
    else if ([kind isEqualToString:@"source"]) { if (self.openNetworkSource) self.openNetworkSource(entry[@"source"]); }
    else [self enqueueEntry:entry play:YES];
}
- (void)enqueueEntry:(NSDictionary *)entry play:(BOOL)play
{
    id<VLCMediaLibraryItemProtocol> item = entry[@"item"];
    if (item) { [VLCMain.sharedInstance.libraryController appendItemsToPlayQueue:item.mediaItems playFirstItemImmediately:play]; return; }
    NSURL *url = entry[@"url"]; if (!url) return;
    VLCOpenInputMetadata *metadata = [[VLCOpenInputMetadata alloc] init]; metadata.MRLString = url.absoluteString;
    [self.queue addPlayQueueItems:@[metadata] atPosition:NSUIntegerMax startPlayback:play];
}
- (VLCMediaLibraryPlaylist *)currentPlaylist
{
    id item = self.state[@"item"];
    return [item isKindOfClass:VLCMediaLibraryPlaylist.class] ? item : nil;
}
- (BOOL)appendMetadataToPlaylist:(NSArray<VLCOpenInputMetadata *> *)metadata
{
    VLCMediaLibraryPlaylist *playlist = [self currentPlaylist];
    if (!playlist || playlist.readOnly) return NO;
    NSMutableArray *items = [NSMutableArray array];
    for (VLCOpenInputMetadata *entry in metadata) {
        NSURL *url = [NSURL URLWithString:entry.MRLString];
        VLCMediaLibraryMediaItem *item = [VLCMediaLibraryMediaItem mediaItemForURL:url] ?: [[VLCMediaLibraryMediaItem alloc] initWithExternalURL:url];
        if (item) [items addObject:item];
    }
    BOOL result = [playlist appendMediaItems:items];
    if (result) [self reload];
    return result;
}
- (void)addMedia:(id)sender
{
    NSString *mode = self.state[@"mode"];
    if ([mode isEqualToString:@"network"]) { [VLCMain.sharedInstance.open openNet]; return; }
    if ([mode isEqualToString:@"playlists"]) {
        NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = _NS("Create playlist"); [alert addButtonWithTitle:_NS("Create")]; [alert addButtonWithTitle:_NS("Cancel")];
        NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,280,28)]; name.cell = [[VLCRedesignAlignedTextFieldCell alloc] initTextCell:@""]; name.editable = YES; name.selectable = YES; name.usesSingleLineMode = YES; name.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular]; name.placeholderString = _NS("Playlist name"); alert.accessoryView = name;
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            NSString *title = [name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (response != NSAlertFirstButtonReturn || !title.length) return;
            vlc_medialibrary_t *library = vlc_ml_instance_get(getIntf()); if (!library) return;
            vlc_ml_playlist_t *playlist = vlc_ml_playlist_create(library,title.UTF8String); if (playlist) vlc_ml_playlist_release(playlist); else NSBeep();
            [self reload];
        }]; return;
    }
    NSOpenPanel *picker = NSOpenPanel.openPanel; picker.canChooseDirectories = ![self currentPlaylist]; picker.canChooseFiles = ![@[@"folders",@"music"] containsObject:mode]; picker.allowsMultipleSelection = YES;
    [picker beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSMutableArray *metadata = [NSMutableArray array];
        for (NSURL *url in picker.URLs) {
            NSNumber *directory; [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
            if (directory.boolValue) [VLCMain.sharedInstance.libraryController addFolderWithFileURL:url];
            else [metadata addObject:[VLCOpenInputMetadata inputMetaWithPath:url.path]];
        }
        if (metadata.count) {
            if ([self currentPlaylist]) { if (![self appendMetadataToPlaylist:metadata]) NSBeep(); }
            else [self.queue addPlayQueueItems:metadata atPosition:NSUIntegerMax startPlayback:NO];
        }
        [self reload];
    }];
}
- (void)expand { [self closePopup]; if (self.expandLibrary) self.expandLibrary(self.currentFolderURL,[self.state[@"section"] integerValue],_gridMode); }
- (void)showParents:(id)sender
{
    NSString *path = self.currentFolderURL.path.stringByStandardizingPath; if (!path.length) return;
    NSMenu *menu = [[NSMenu alloc] init];
    while (path.length) {
        NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
        NSMenuItem *item = [menu addItemWithTitle:[path isEqualToString:@"/"] ? @"/" : path.lastPathComponent action:@selector(openParent:) keyEquivalent:@""]; item.target = self; item.representedObject = url;
        if ([path isEqualToString:@"/"]) break;
        NSString *parent = path.stringByDeletingLastPathComponent;
        if (parent.length >= path.length) break;
        path = parent;
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,24) inView:_address];
}
- (void)openParent:(NSMenuItem *)sender { [self browseFolder:sender.representedObject]; }
- (void)showSort
{
    NSMenu *menu = [[NSMenu alloc] init]; menu.autoenablesItems = NO;
    BOOL hasDate = NO, hasWatchedState = NO;
    for (NSDictionary *entry in _rawEntries) { hasDate |= entry[@"modified"] != nil; hasWatchedState |= entry[@"played"] != nil; }
    NSArray *names = @[_NS("Name (A–Z)"),_NS("Name (Z–A)"),_NS("Date modified"),_NS("Unwatched first"),_NS("Watched first")];
    for (NSInteger i=0;i<(NSInteger)names.count;i++) { NSMenuItem *item = [menu addItemWithTitle:names[i] action:@selector(sort:) keyEquivalent:@""]; item.target = self; item.tag = i; item.state = i == _sortMode ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = i < 2 || (i == 2 ? hasDate : hasWatchedState); }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,24) inView:_sortButton];
}
- (void)sort:(NSMenuItem *)sender { _sortMode = sender.tag; [self applyFilter]; }
- (void)showActions
{
    NSMenu *menu = [[NSMenu alloc] init];
    for (NSArray *entry in @[@[_NS("Add media…"),NSStringFromSelector(@selector(addMedia:))],@[_NS("Refresh"),NSStringFromSelector(@selector(refresh:))],@[_NS("Browse parent folders"),NSStringFromSelector(@selector(showParents:))],@[_NS("Open full library"),NSStringFromSelector(@selector(expand:))]]) { NSMenuItem *item = [menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""]; item.target = self; }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,24) inView:_moreButton];
}
- (void)refresh:(id)sender { [self reload]; }
- (void)expand:(id)sender { [self expand]; }
- (void)showViewOptions
{
    if (_viewPopup) { [self closePopup]; return; }
    VLCBrowserSurface *content = [[VLCBrowserSurface alloc] initWithFrame:NSMakeRect(0,0,265,104)]; content.wantsLayer = YES; content.layer.cornerRadius = 10; content.layer.backgroundColor = [[VLCRedesignAppearance colorWithRGB:0x191919] colorWithAlphaComponent:.95].CGColor;
    __weak typeof(self) weakSelf = self;
    for (NSInteger i=0;i<2;i++) {
        VLCBrowserViewOption *button = [[VLCBrowserViewOption alloc] init]; button.frame = NSMakeRect(4,4+i*48,257,48); button.gridIcon = i == 0; button.chosen = _gridMode == (i == 0); button.title = i == 0 ? _NS("Grid View") : _NS("List View"); button.accessibilityLabel = button.title;
        button.activate = ^{ weakSelf.gridMode = i == 0; [NSUserDefaults.standardUserDefaults setBool:weakSelf.gridMode forKey:@"VLCRedesignCompactGrid"]; [weakSelf closePopup]; weakSelf.scroll.documentView = weakSelf.gridMode ? weakSelf.grid : weakSelf.table; [weakSelf applyFilter]; };
        [content addSubview:button];
    }
    _viewPopup = [[VLCBrowserPopup alloc] initWithContentRect:content.bounds styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _viewPopup.contentView = content; _viewPopup.backgroundColor = NSColor.clearColor; _viewPopup.opaque = NO; _viewPopup.hasShadow = YES; _viewPopup.releasedWhenClosed = NO; _viewPopup.hidesOnDeactivate = YES;
    NSRect anchor = [self.window convertRectToScreen:[_viewButton convertRect:_viewButton.bounds toView:nil]];
    NSRect screen = self.window.screen.visibleFrame;
    CGFloat x = MAX(NSMinX(screen),MIN(NSMaxX(anchor)-265,NSMaxX(screen)-265));
    [_viewPopup setFrameOrigin:NSMakePoint(x,MAX(NSMinY(screen),NSMinY(anchor)-110))];
    [self.window addChildWindow:_viewPopup ordered:NSWindowAbove]; [_viewPopup makeKeyAndOrderFront:nil];
    _popupMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        typeof(self) browser = weakSelf; if (!browser) return event;
        if (event.type == NSEventTypeKeyDown && event.keyCode == 53) { [browser closePopup]; return nil; }
        if (event.type == NSEventTypeLeftMouseDown && event.window != browser.viewPopup) {
            NSPoint point = [browser.viewButton convertPoint:event.locationInWindow fromView:nil];
            if (event.window != browser.window || !NSPointInRect(point,browser.viewButton.bounds)) [browser closePopup];
        }
        return event;
    }];
}
- (void)closePopupNotification:(NSNotification *)notification { [self closePopup]; }
- (void)closePopup
{
    NSWindow *parent = _viewPopup.parentWindow; [parent removeChildWindow:_viewPopup]; [_viewPopup orderOut:nil]; _viewPopup = nil;
    if (_popupMonitor) { [NSEvent removeMonitor:_popupMonitor]; _popupMonitor = nil; }
    if (parent.visible && NSApp.active) [parent makeKeyWindow];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return _entries.count; }
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row { return [[VLCBrowserRow alloc] init]; }
- (void)configureArtwork:(VLCBrowserArtwork *)artwork entry:(NSDictionary *)entry large:(BOOL)large changed:(void (^)(NSImage *))changed
{
    NSString *icon = entry[@"icon"];
    if (!icon && [entry[@"kind"] isEqualToString:@"folder"]) icon = @"folder";
    if (!icon && [entry[@"kind"] isEqualToString:@"playlist"]) icon = @"playlists";
    artwork.mirrorIcon = [@[@"folder",@"songs",@"albums"] containsObject:icon ?: @""];
    artwork.intrinsicAsset = icon.length > 0; artwork.image = icon.length ? VLCBrowserAsset(icon) : nil;
    artwork.progress = [entry[@"progress"] doubleValue]; artwork.needsDisplay = YES;
    if (icon.length) return;
    NSURL *url = entry[@"url"]; if (!url.isFileURL) return;
    NSDate *modified = entry[@"modified"];
    NSString *key = [NSString stringWithFormat:@"%@:%f:%d",url.absoluteString,modified.timeIntervalSince1970,large];
    NSImage *cached = [_artworkCache objectForKey:key]; if (cached) { artwork.image = cached; return; }
    if (_pendingArtwork[key]) { if (changed) [_pendingArtwork[key] addObject:[changed copy]]; return; }
    _pendingArtwork[key] = [NSMutableArray array];
    if (changed) [_pendingArtwork[key] addObject:[changed copy]];
    VLCInputItem *input = [VLCInputItem inputItemFromURL:url];
    __weak typeof(self) weakSelf = self;
    [input thumbnailWithSize:large ? NSMakeSize(320,180) : NSMakeSize(64,64) completionHandler:^(NSImage *image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) browser = weakSelf; if (!browser) return;
            NSArray *callbacks = browser.pendingArtwork[key].copy;
            [browser.pendingArtwork removeObjectForKey:key];
            if (image) [browser.artworkCache setObject:image forKey:key cost:(NSUInteger)(large ? 320*180*4 : 64*64*4)];
            for (void (^callback)(NSImage *) in callbacks) callback(image);
        });
    }];
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    VLCBrowserCell *cell = [tableView makeViewWithIdentifier:@"browser-media" owner:self];
    if (!cell) { cell = [[VLCBrowserCell alloc] init]; cell.identifier = @"browser-media"; }
    NSDictionary *entry = _entries[row]; NSURL *url = entry[@"url"]; cell.representedURL = url;
    cell.textField.stringValue = entry[@"name"]; cell.textField.toolTip = entry[@"name"];
    __weak VLCBrowserCell *weakCell = cell;
    [self configureArtwork:cell.artwork entry:entry large:NO changed:^(NSImage *image) {
        if ([weakCell.representedURL isEqual:url]) { weakCell.artwork.image = image; weakCell.artwork.needsDisplay = YES; }
    }];
    return cell;
}
- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return _entries.count; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    VLCBrowserGridItem *item = [collectionView makeItemWithIdentifier:@"media" forIndexPath:indexPath];
    NSDictionary *entry = _entries[indexPath.item]; NSURL *url = entry[@"url"];
    item.representedURL = url; item.textField.stringValue = entry[@"name"]; item.textField.toolTip = entry[@"name"];
    __weak typeof(self) weakSelf = self; __weak VLCBrowserGridItem *weakItem = item;
    item.activate = ^{ [weakSelf activateEntry:entry]; };
    [self configureArtwork:item.artwork entry:entry large:YES changed:^(NSImage *image) {
        if ([weakItem.representedURL isEqual:url]) { weakItem.artwork.image = image; weakItem.artwork.needsDisplay = YES; }
    }];
    return item;
}
- (id<NSPasteboardWriting>)pasteboardForEntry:(NSDictionary *)entry
{
    id<VLCMediaLibraryItemProtocol> libraryItem = entry[@"item"];
    if (libraryItem) return [NSPasteboardItem pasteboardItemWithLibraryItem:libraryItem];
    NSURL *url = entry[@"url"];
    return url; /* NSURL provides modern native file-URL/URL drag types. */
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    msg_Dbg(getIntf(), "compact browser drag begins at row %ld",row);
    return [self pasteboardForEntry:_entries[row]];
}
- (id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath { return [self pasteboardForEntry:_entries[indexPath.item]]; }
- (BOOL)collectionView:(NSCollectionView *)collectionView canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths withEvent:(NSEvent *)event
{
    for (NSIndexPath *path in indexPaths) if (_entries[path.item][@"url"] || _entries[path.item][@"item"]) return YES;
    return NO;
}
- (BOOL)acceptPasteboard:(NSPasteboard *)pasteboard
{
    /* Library drags preserve their IDs; file/URL drops explicitly enqueue and
     * never inherit the open-file autoplay preference. */
    if ([pasteboard availableTypeFromArray:@[VLCMediaLibraryMediaItemUTI,VLCMediaLibraryMediaItemPasteboardType]]) {
        VLCMediaLibraryPlaylist *playlist = [self currentPlaylist];
        if (!playlist) return [VLCFileDragRecognisingView handlePasteboardFromDragSessionAsPlayQueueItems:pasteboard];
        NSMutableArray *items = [NSMutableArray array];
        for (NSPasteboardItem *entry in pasteboard.pasteboardItems) {
            NSData *data = [entry dataForType:VLCMediaLibraryMediaItemPasteboardType] ?: [entry dataForType:VLCMediaLibraryMediaItemUTI];
            if (data) [items addObjectsFromArray:[VLCMediaLibraryMediaItem mediaItemsFromPasteboardData:data] ?: @[]];
        }
        BOOL result = [playlist appendMediaItems:items]; if (result) [self reload]; return result;
    }
    NSArray *metadata = [VLCFileDragRecognisingView inputMetadataFromPasteboard:pasteboard];
    if (!metadata.count) return NO;
    if ([self currentPlaylist]) return [self appendMetadataToPlaylist:metadata];
    [self.queue addPlayQueueItems:metadata atPosition:NSUIntegerMax startPlayback:NO]; return YES;
}
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{ return info.draggingSource == tableView ? NSDragOperationNone : NSDragOperationCopy; }
- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation { return [self acceptPasteboard:info.draggingPasteboard]; }
- (NSDragOperation)collectionView:(NSCollectionView *)collectionView validateDrop:(id<NSDraggingInfo>)info proposedIndexPath:(NSIndexPath * _Nonnull * _Nonnull)indexPath dropOperation:(NSCollectionViewDropOperation *)operation
{ return info.draggingSource == collectionView ? NSDragOperationNone : NSDragOperationCopy; }
- (BOOL)collectionView:(NSCollectionView *)collectionView acceptDrop:(id<NSDraggingInfo>)info indexPath:(NSIndexPath *)indexPath dropOperation:(NSCollectionViewDropOperation)operation { return [self acceptPasteboard:info.draggingPasteboard]; }
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    if (_gridMode) {
        NSPoint point = [_grid convertPoint:NSApp.currentEvent.locationInWindow fromView:nil];
        NSIndexPath *path = [_grid indexPathForItemAtPoint:point]; if (path) _grid.selectionIndexPaths = [NSSet setWithObject:path];
    }
    if (!_gridMode && _table.clickedRow >= 0) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:_table.clickedRow] byExtendingSelection:NO];
    NSInteger index = self.selectedIndex; if (index < 0 || index >= (NSInteger)_entries.count) return;
    NSDictionary *entry = _entries[index]; NSString *kind = entry[@"kind"];
    NSMenuItem *open = [menu addItemWithTitle:[@[@"folder",@"playlist",@"group",@"category",@"source"] containsObject:kind] ? _NS("Open") : _NS("Play") action:@selector(activateSelected:) keyEquivalent:@""]; open.target = self;
    if (entry[@"url"] || entry[@"item"]) { NSMenuItem *enqueue = [menu addItemWithTitle:_NS("Add to queue") action:@selector(enqueueSelected:) keyEquivalent:@""]; enqueue.target = self; }
    if (((NSURL *)entry[@"url"]).isFileURL) { NSMenuItem *reveal = [menu addItemWithTitle:_NS("Show in Finder") action:@selector(revealSelected:) keyEquivalent:@""]; reveal.target = self; }
    if ([kind isEqualToString:@"playlist"]) { NSMenuItem *rename = [menu addItemWithTitle:_NS("Rename…") action:@selector(renamePlaylist:) keyEquivalent:@""]; rename.target = self; }
}
- (void)enqueueSelected:(id)sender { NSInteger index = self.selectedIndex; if (index >= 0 && index < (NSInteger)_entries.count) [self enqueueEntry:_entries[index] play:NO]; }
- (void)revealSelected:(id)sender { NSInteger index = self.selectedIndex; if (index >= 0 && index < (NSInteger)_entries.count) { NSURL *url = _entries[index][@"url"]; if (url.isFileURL) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]]; } }
- (void)renamePlaylist:(id)sender
{
    NSInteger index = self.selectedIndex; if (index < 0 || index >= (NSInteger)_entries.count) return;
    VLCMediaLibraryPlaylist *playlist = _entries[index][@"item"];
    if ([playlist isKindOfClass:VLCMediaLibraryPlaylist.class]) { [VLCMain.sharedInstance.libraryController showRenamePlaylistDialogForPlaylist:playlist]; [self reload]; }
}
- (void)progressChanged:(NSNotification *)notification
{
    NSURL *url = self.queue.playerController.URLOfCurrentMediaItem; CGFloat progress = self.queue.playerController.position;
    if (!url) return;
    if (_gridMode) for (VLCBrowserGridItem *item in _grid.visibleItems) {
        if ([item.representedURL isEqual:url]) { item.artwork.progress = progress; item.artwork.needsDisplay = YES; }
    } else {
        NSRange range = [_table rowsInRect:_table.visibleRect];
        for (NSUInteger row=range.location;row<NSMaxRange(range) && row<_entries.count;row++) {
            VLCBrowserCell *cell = [_table viewAtColumn:0 row:row makeIfNecessary:NO];
            if ([cell.representedURL isEqual:url]) { cell.artwork.progress = progress; cell.artwork.needsDisplay = YES; }
        }
    }
}
- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds), content = MAX(0,width-90);
    _rail.frame = NSMakeRect(0,0,50,height);
    for (NSUInteger i=0;i<_railButtons.count;i++) _railButtons[i].frame = NSMakeRect(10,8+i*46,30,32);
    _backButton.frame = NSMakeRect(70,20,24,24); _forwardButton.frame = NSMakeRect(106,20,24,24);
    _address.frame = NSMakeRect(140,20,MAX(0,width-240),24);
    _moreButton.frame = NSMakeRect(width-80,20,24,24); _expandButton.frame = NSMakeRect(width-44,20,24,24);
    _counter.frame = NSMakeRect(70,64,MAX(0,content-108),24);
    _sortButton.frame = NSMakeRect(width-116,64,24,24); _viewButton.frame = NSMakeRect(width-80,64,24,24); _searchButton.frame = NSMakeRect(width-44,64,24,24);
    _searchField.frame = NSMakeRect(70,60,MAX(0,width-126),32);
    _divider.frame = NSMakeRect(70,104,content,1);
    _scroll.frame = NSMakeRect(70,125,content,MAX(0,height-145)); [_scroll tile];
    CGFloat bodyWidth = NSWidth(_scroll.contentView.bounds);
    if (_gridMode) {
        NSUInteger columns = bodyWidth >= 300 ? 2 : 1; CGFloat itemWidth = MAX(0,(bodyWidth-(columns-1)*10)/columns);
        _gridLayout.itemSize = NSMakeSize(itemWidth,itemWidth*9./16.+46);
        NSUInteger rows = (_entries.count+columns-1)/columns;
        CGFloat contentHeight = rows ? rows*_gridLayout.itemSize.height+(rows-1)*10 : 0;
        _grid.frame = NSMakeRect(0,0,bodyWidth,MAX(contentHeight,NSHeight(_scroll.contentView.bounds)));
    } else {
        _table.frame = NSMakeRect(0,0,bodyWidth,MAX(NSHeight(_scroll.contentView.bounds),_entries.count*42));
        _table.tableColumns.firstObject.width = bodyWidth;
    }
    _message.frame = NSMakeRect(70,125,content,80);
}
@end
