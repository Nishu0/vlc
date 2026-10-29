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

static VLCRedesignAlignedLabel *VLCBrowserLabel(CGFloat size, NSColor *color)
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:@""];
    label.font = [VLCRedesignAppearance fontOfSize:size weight:NSFontWeightRegular];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}

/* Active sidebar icons are single-colour shapes; tinting follows the chosen accent. */
static NSImage *VLCBrowserTinted(NSImage *image, NSColor *color)
{
    if (!image)
        return nil;
    return [NSImage imageWithSize:image.size
                          flipped:NO
                   drawingHandler:^BOOL(NSRect rect) {
                       [image drawInRect:rect];
                       [color set];
                       NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
                       return YES;
                   }];
}

static void VLCBrowserDrawGridIcon(NSRect rect)
{
    [VLCRedesignAppearance.subduedColor setStroke];
    for (NSUInteger row = 0; row < 2; row++)
        for (NSUInteger column = 0; column < 2; column++) {
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(rect.origin.x + 1 + column * 12,
                                                                                    rect.origin.y + 3 + row * 10, 10, 8)
                                                                 xRadius:2
                                                                 yRadius:2];
            path.lineWidth = 1.5;
            [path stroke];
        }
}

@interface VLCBrowserModeButton : VLCRedesignPanelButton
@property BOOL gridIcon;
@end
@implementation VLCBrowserModeButton

- (void)drawRect:(NSRect)dirtyRect
{
    if (!self.gridIcon) {
        [super drawRect:dirtyRect];
        return;
    }
    if (self.highlighted) {
        [VLCRedesignAppearance.dividerColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
    }
    VLCBrowserDrawGridIcon(NSMakeRect(NSMidX(self.bounds) - 12, NSMidY(self.bounds) - 12, 24, 24));
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:4 yRadius:4] stroke];
    }
}

@end
@interface VLCBrowserAddressButton : NSButton
// Path shown as "Videos ▸ Shows ▸ S01", the last component emphasised
@property (copy) NSArray<NSString *> *crumbs;
@end
@implementation VLCBrowserAddressButton

- (void)drawBreadcrumbs
{
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    NSDictionary *separator = @{
        NSFontAttributeName : [VLCRedesignAppearance fontOfSize:8 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : VLCRedesignAppearance.borderColor,
        NSBaselineOffsetAttributeName : @3
    };
    for (NSUInteger i = 0; i < _crumbs.count; i++) {
        BOOL last = i + 1 == _crumbs.count;
        if (i > 0)
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"  ▶  " attributes:separator]];
        [text appendAttributedString:[[NSAttributedString alloc]
                                         initWithString:_crumbs[i]
                                             attributes:@{
                                                 NSFontAttributeName : [VLCRedesignAppearance
                                                     fontOfSize:16
                                                         weight:last ? NSFontWeightSemibold : NSFontWeightRegular],
                                                 NSForegroundColorAttributeName : last ? VLCRedesignAppearance.subduedColor
                                                                                       : VLCRedesignAppearance.mutedColor
                                             }]];
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingHead;
    [text addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, text.length)];
    VLCDrawAlignedText(text, self.bounds, self.flipped, NSTextAlignmentLeft);
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (_crumbs.count) {
        [self drawBreadcrumbs];
        return;
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSAttributedString *text = [[NSAttributedString alloc]
        initWithString:self.title
            attributes:@{
                NSFontAttributeName : [VLCRedesignAppearance fontOfSize:16 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : VLCRedesignAppearance.subduedColor,
                NSParagraphStyleAttributeName : style
            }];
    VLCDrawAlignedText(text, self.bounds, self.flipped, NSTextAlignmentLeft);
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        [NSBezierPath strokeRect:NSInsetRect(self.bounds, 1, 1)];
    }
}

@end
@interface VLCBrowserSurface : NSView
@end
@implementation VLCBrowserSurface

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

@end

/* SVGs keep their intrinsic size; media thumbnails alone fill/crop their slot. */
@interface VLCBrowserArtwork : NSImageView
@property BOOL intrinsicAsset;
@property CGFloat progress;
@property CGFloat cornerRadius;
// Icons drawn at this size instead of their intrinsic one, when set
@property CGFloat iconSize;
@property (nullable) NSColor *fillColor;
@end
@implementation VLCBrowserArtwork

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [NSGraphicsContext saveGraphicsState];
    CGFloat radius = self.cornerRadius > 0 ? self.cornerRadius : 2;
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] addClip];
    if (!self.intrinsicAsset || self.fillColor) {
        [(self.fillColor ?: VLCRedesignAppearance.hoverColor) setFill];
        NSRectFill(self.bounds);
    }
    NSSize size = self.intrinsicAsset && self.iconSize > 0 ? NSMakeSize(self.iconSize, self.iconSize) : self.image.size;
    if (size.width > 0 && size.height > 0) {
        CGFloat scale =
            self.intrinsicAsset ? 1 : MAX(NSWidth(self.bounds) / size.width, NSHeight(self.bounds) / size.height);
        NSRect rect =
            NSMakeRect(NSMidX(self.bounds) - size.width * scale / 2, NSMidY(self.bounds) - size.height * scale / 2,
                       size.width * scale, size.height * scale);
        [self.image drawInRect:rect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1
                respectFlipped:YES
                         hints:nil];
    }
    if (self.progress > 0) {
        [VLCRedesignAppearance.accentColor setFill];
        NSRectFill(NSMakeRect(0, self.flipped ? NSHeight(self.bounds) - 3 : 0,
                              MAX(0, MIN(1, self.progress)) * NSWidth(self.bounds), 3));
    }
    [NSGraphicsContext restoreGraphicsState];
}

@end
@interface VLCBrowserCell : NSTableCellView
@property VLCBrowserArtwork *artwork;
@property NSURL *representedURL;
@property NSDictionary *representedEntry;
@end
@implementation VLCBrowserCell

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.textField = VLCBrowserLabel(14, VLCRedesignAppearance.subduedColor);
        _artwork = [[VLCBrowserArtwork alloc] init];
        [self addSubview:_artwork];
        [self addSubview:self.textField];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _artwork.frame = NSMakeRect(0, 0, 32, 32);
    self.textField.frame = NSMakeRect(42, 0, MAX(0, NSWidth(self.bounds) - 42), 32);
}

@end
@interface VLCBrowserTable : NSTableView
@property (copy) void (^activateRow)(void);
@end
@implementation VLCBrowserTable

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.activateRow)
            self.activateRow();
    } else
        [super keyDown:event];
}

@end
@interface VLCBrowserRow : NSTableRowView
@end
@implementation VLCBrowserRow

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    [VLCRedesignAppearance.accentBackingColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
}

@end
@interface VLCBrowserGridItem : NSCollectionViewItem
@property VLCBrowserArtwork *artwork;
@property NSURL *representedURL;
@property NSDictionary *representedEntry;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserGridItem

- (void)loadView
{
    self.view = [[VLCBrowserSurface alloc] init];
    _artwork = [[VLCBrowserArtwork alloc] init];
    NSTextField *caption = VLCBrowserLabel(16, VLCRedesignAppearance.subduedColor);
    [self.view addSubview:caption];
    self.textField = caption;
    self.textField.maximumNumberOfLines = 1;
    self.textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:_artwork];
    _artwork.translatesAutoresizingMaskIntoConstraints = self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_artwork.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_artwork.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_artwork.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_artwork.heightAnchor constraintEqualToAnchor:_artwork.widthAnchor multiplier:9. / 16.],
        [self.textField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textField.topAnchor constraintEqualToAnchor:_artwork.bottomAnchor constant:8],
        [self.textField.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    NSClickGestureRecognizer *gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(open:)];
    gesture.numberOfClicksRequired = 2;
    gesture.delaysPrimaryMouseButtonEvents = NO;
    [self.view addGestureRecognizer:gesture];
}

- (void)open:(id)sender
{
    if (self.activate)
        self.activate();
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.view.wantsLayer = YES;
    self.view.layer.borderWidth = selected ? 2 : 0;
    self.view.layer.cornerRadius = 4;
    self.view.layer.borderColor = VLCRedesignAppearance.accentColor.CGColor;
}

@end
@interface VLCBrowserGrid : NSCollectionView
@property (copy) void (^activateItem)(void);
@end
@implementation VLCBrowserGrid

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.activateItem)
            self.activateItem();
    } else
        [super keyDown:event];
}

@end

/* Full library sidebar entry: icon and label, accent icon when chosen. */
@interface VLCBrowserSidebarItem : NSButton
@property (copy) NSString *role;
@property BOOL chosen;
@property BOOL iconOnly;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserSidebarItem

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.bordered = NO;
        self.title = @"";
        self.target = self;
        self.action = @selector(invoke:);
    }
    return self;
}

- (void)invoke:(id)sender
{
    if (self.activate)
        self.activate();
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.highlighted) {
        [VLCRedesignAppearance.hoverColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
    }
    NSImage *icon = nil;
    if (self.chosen) {
        icon = VLCBrowserAsset([_role stringByAppendingString:@"-active"]) ?: VLCBrowserAsset(_role);
        icon = VLCBrowserTinted(icon, VLCRedesignAppearance.accentColor);
    } else
        icon = VLCBrowserAsset(_role);
    CGFloat x = self.iconOnly ? floor((NSWidth(self.bounds) - 24) / 2) : 3;
    [icon drawInRect:NSMakeRect(x, floor((NSHeight(self.bounds) - 24) / 2), 24, 24)
            fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver
            fraction:1
      respectFlipped:YES
               hints:nil];
    if (!self.iconOnly) {
        NSAttributedString *text = [[NSAttributedString alloc]
            initWithString:self.accessibilityLabel ?: @""
                attributes:@{
                    NSFontAttributeName : [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName : self.chosen ? VLCRedesignAppearance.secondaryColor
                                                                 : VLCRedesignAppearance.subduedColor
                }];
        VLCDrawAlignedText(text, NSMakeRect(38, 0, MAX(0, NSWidth(self.bounds) - 38), NSHeight(self.bounds)), YES,
                           NSTextAlignmentLeft);
    }
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:4 yRadius:4] stroke];
    }
}

@end

typedef NS_ENUM(NSInteger, VLCBrowserTileStyle) {
    VLCBrowserTileVideo,  // 16:9 thumbnail
    VLCBrowserTileSquare, // album artwork with a second line
    VLCBrowserTileFolder, // plain tile with a large folder icon
};

static const CGFloat VLCBrowserTileCaptionGap = 20;
static const CGFloat VLCBrowserTileLineHeight = 20;

/* Large full-library tile, laid out by frame so every style shares one class. */
@interface VLCBrowserTileView : VLCBrowserSurface
@property VLCBrowserArtwork *artwork;
@property VLCRedesignAlignedLabel *title;
@property VLCRedesignAlignedLabel *subtitle;
@property VLCBrowserTileStyle style;
@end
@implementation VLCBrowserTileView

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _artwork = [[VLCBrowserArtwork alloc] init];
        _artwork.cornerRadius = 12;
        _title = VLCBrowserLabel(16, VLCRedesignAppearance.subduedColor);
        _subtitle = VLCBrowserLabel(16, VLCRedesignAppearance.mutedColor);
        [self addSubview:_artwork];
        [self addSubview:_title];
        [self addSubview:_subtitle];
    }
    return self;
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    CGFloat artHeight = _style == VLCBrowserTileVideo ? floor(width * 9. / 16.) : width;
    _artwork.frame = NSMakeRect(0, 0, width, artHeight);
    _title.frame = NSMakeRect(0, artHeight + VLCBrowserTileCaptionGap, width, VLCBrowserTileLineHeight);
    _subtitle.frame = NSMakeRect(0, NSMaxY(_title.frame) + 10, width, VLCBrowserTileLineHeight);
    _subtitle.hidden = _style != VLCBrowserTileSquare;
}

@end

@interface VLCBrowserTileItem : NSCollectionViewItem
@property VLCBrowserTileView *tile;
@property NSURL *representedURL;
@property NSDictionary *representedEntry;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserTileItem

- (void)loadView
{
    _tile = [[VLCBrowserTileView alloc] init];
    self.view = _tile;
    NSClickGestureRecognizer *gesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(open:)];
    gesture.numberOfClicksRequired = 2;
    gesture.delaysPrimaryMouseButtonEvents = NO;
    [self.view addGestureRecognizer:gesture];
}

- (VLCBrowserArtwork *)artwork
{
    return _tile.artwork;
}

- (void)open:(id)sender
{
    if (self.activate)
        self.activate();
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    _tile.artwork.wantsLayer = YES;
    _tile.artwork.layer.borderWidth = selected ? 2 : 0;
    _tile.artwork.layer.cornerRadius = 12;
    _tile.artwork.layer.borderColor = VLCRedesignAppearance.accentColor.CGColor;
}

@end

/* "Continue Watching ›" heading above a Home section; clicking opens the full list. */
@interface VLCBrowserSectionHeader : VLCBrowserSurface <NSCollectionViewElement>
@property (copy) NSString *title;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserSectionHeader

- (void)drawRect:(NSRect)dirtyRect
{
    NSAttributedString *text =
        [[NSAttributedString alloc] initWithString:_title ?: @""
                                        attributes:@{
                                            NSFontAttributeName : [VLCRedesignAppearance fontOfSize:20
                                                                                             weight:NSFontWeightRegular],
                                            NSForegroundColorAttributeName : VLCRedesignAppearance.subduedColor
                                        }];
    NSRect slot = NSMakeRect(0, 0, text.size.width + 1, NSHeight(self.bounds));
    VLCDrawAlignedText(text, slot, YES, NSTextAlignmentLeft);
    if (!self.activate)
        return;
    NSBezierPath *chevron = [NSBezierPath bezierPath];
    CGFloat x = NSMaxX(slot) + 9, y = floor(NSMidY(self.bounds));
    [chevron moveToPoint:NSMakePoint(x, y - 5)];
    [chevron lineToPoint:NSMakePoint(x + 5, y)];
    [chevron lineToPoint:NSMakePoint(x, y + 5)];
    chevron.lineWidth = 1.5;
    chevron.lineCapStyle = NSLineCapStyleRound;
    chevron.lineJoinStyle = NSLineJoinStyleRound;
    [VLCRedesignAppearance.subduedColor setStroke];
    [chevron stroke];
}

- (void)mouseUp:(NSEvent *)event
{
    if (self.activate)
        self.activate();
}

@end

@interface VLCBrowserViewOption : NSButton
@property BOOL gridIcon;
@property BOOL chosen;
@property (copy) void (^activate)(void);
@end
@implementation VLCBrowserViewOption

- (BOOL)isFlipped
{
    return YES;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.bordered = NO;
        self.target = self;
        self.action = @selector(invoke:);
    }
    return self;
}

- (void)invoke:(id)sender
{
    if (self.activate)
        self.activate();
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.chosen || self.highlighted) {
        [VLCRedesignAppearance.hoverColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    }
    NSRect icon = NSMakeRect(14, 12, 24, 24);
    if (self.gridIcon) {
        VLCBrowserDrawGridIcon(icon);
    } else
        [VLCBrowserAsset(@"list-view") drawInRect:icon
                                         fromRect:NSZeroRect
                                        operation:NSCompositingOperationSourceOver
                                         fraction:1
                                   respectFlipped:YES
                                            hints:nil];
    NSAttributedString *text = [[NSAttributedString alloc]
        initWithString:self.title
            attributes:@{
                NSFontAttributeName : [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : VLCRedesignAppearance.subduedColor
            }];
    VLCDrawAlignedText(text, NSMakeRect(48, 0, MAX(0, NSWidth(self.bounds) - 100), 48), YES, NSTextAlignmentLeft);
    if (self.chosen)
        [VLCRedesignPanelImage(@"VLC-redesign-tracks-check")
                drawInRect:NSMakeRect(NSWidth(self.bounds) - 38, 12, 24, 24)
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1
            respectFlipped:YES
                     hints:nil];
}

@end
@interface VLCBrowserPopup : NSPanel
@end
@implementation VLCBrowserPopup

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

@end

static NSArray<VLCMediaLibraryPlaylist *> *VLCBrowserFetchPlaylists(vlc_medialibrary_t *library)
{
    if (!library)
        return @[];
    vlc_ml_playlist_list_t *list = vlc_ml_list_playlists(library, NULL, VLC_ML_PLAYLIST_TYPE_ALL);
    if (!list)
        return @[];
    NSMutableArray<VLCMediaLibraryPlaylist *> *items = [NSMutableArray arrayWithCapacity:list->i_nb_items];
    for (size_t i = 0; i < list->i_nb_items; i++) {
        VLCMediaLibraryPlaylist *item = [[VLCMediaLibraryPlaylist alloc] initWithPlaylist:&list->p_items[i]];
        if (item)
            [items addObject:item];
    }
    vlc_ml_playlist_list_release(list);
    return items.copy;
}

static NSArray<VLCMediaLibraryMediaItem *> *
VLCBrowserFetchGroupMedia(vlc_medialibrary_t *library, VLCMediaLibraryParentGroupType groupType, int64_t groupID)
{
    if (!library || groupID <= 0 || groupType == VLCMediaLibraryParentGroupTypeUnknown)
        return @[];
    vlc_ml_media_list_t *list = vlc_ml_list_media_of(library, NULL, groupType, groupID);
    if (!list)
        return @[];
    NSMutableArray<VLCMediaLibraryMediaItem *> *items = [NSMutableArray arrayWithCapacity:list->i_nb_items];
    for (size_t i = 0; i < list->i_nb_items; i++) {
        VLCMediaLibraryMediaItem *item = [[VLCMediaLibraryMediaItem alloc] initWithMediaItem:&list->p_items[i]];
        if (item)
            [items addObject:item];
    }
    vlc_ml_media_list_release(list);
    return items.copy;
}

typedef NS_ENUM(NSInteger, VLCBrowserMode) {
    VLCBrowserModeFolders,
    VLCBrowserModeDirectory,
    VLCBrowserModeMusic,
    VLCBrowserModeSongs,
    VLCBrowserModeAlbums,
    VLCBrowserModeArtists,
    VLCBrowserModeGenres,
    VLCBrowserModeNetwork,
    VLCBrowserModePlaylists,
    VLCBrowserModeGroup,
    VLCBrowserModeRecent,
    VLCBrowserModeHome,
};

typedef NS_ENUM(NSInteger, VLCBrowserSortMode) {
    VLCBrowserSortNameAscending,
    VLCBrowserSortNameDescending,
    VLCBrowserSortModificationDate,
    VLCBrowserSortUnwatchedFirst,
    VLCBrowserSortWatchedFirst,
};

/* Navigation snapshots are immutable so a background load cannot observe
 * fields from a different history entry halfway through a query. */
@interface VLCBrowserLocation : NSObject
@property (nonatomic, readonly) VLCRedesignBrowserSection section;
@property (nonatomic, readonly) VLCBrowserMode mode;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) NSURL *folderURL;
@property (nonatomic, readonly) id<VLCMediaLibraryItemProtocol> libraryItem;
- (instancetype)initWithSection:(VLCRedesignBrowserSection)section
                           mode:(VLCBrowserMode)mode
                          title:(NSString *)title
                      folderURL:(NSURL *)folderURL
                    libraryItem:(id<VLCMediaLibraryItemProtocol>)libraryItem;
@end

@implementation VLCBrowserLocation

- (instancetype)initWithSection:(VLCRedesignBrowserSection)section
                           mode:(VLCBrowserMode)mode
                          title:(NSString *)title
                      folderURL:(NSURL *)folderURL
                    libraryItem:(id<VLCMediaLibraryItemProtocol>)libraryItem
{
    self = [super init];
    if (self) {
        _section = section;
        _mode = mode;
        _title = [title copy];
        _folderURL = [folderURL copy];
        _libraryItem = libraryItem;
    }
    return self;
}

@end

static BOOL VLCBrowserModeShowsGroups(VLCBrowserMode mode)
{
    return mode == VLCBrowserModeAlbums || mode == VLCBrowserModeArtists || mode == VLCBrowserModeGenres;
}

static BOOL VLCBrowserModeAllowsAdding(VLCBrowserMode mode)
{
    return mode == VLCBrowserModeFolders || mode == VLCBrowserModeMusic || mode == VLCBrowserModeNetwork ||
           mode == VLCBrowserModePlaylists;
}

static NSString *VLCBrowserGroupIcon(VLCBrowserMode mode)
{
    switch (mode) {
    case VLCBrowserModeAlbums:
        return @"albums";
    case VLCBrowserModeArtists:
        return @"artists";
    case VLCBrowserModeGenres:
        return @"genres";
    default:
        return nil;
    }
}

@interface VLCRedesignCompactBrowser () <NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource,
                                         NSCollectionViewDelegateFlowLayout, NSMenuDelegate, NSTextFieldDelegate>
@property NSView *rail;
// Rounded panel behind the browser content, beside the rail
@property NSView *surface;
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
@property NSMutableArray<VLCBrowserLocation *> *history;
@property NSInteger historyIndex;
@property (atomic) NSUInteger generation;
@property dispatch_queue_t loadQueue;
@property dispatch_source_t directoryWatch;
@property NSCache<NSString *, NSImage *> *artworkCache;
@property NSMutableDictionary<NSString *, NSMutableArray *> *pendingArtwork;
@property VLCBrowserSortMode sortMode;
@property BOOL gridMode;
@property BOOL searchOpen;
@property NSString *loadError;
@property VLCBrowserPopup *viewPopup;
@property id popupMonitor;
@property NSView *sidebarCard;
// Rounded box holding the search icon and field in the full library
@property NSView *searchBox;
@property NSImageView *searchIcon;
@property NSArray<VLCBrowserSidebarItem *> *sidebarItems;
// Grid sections as offsets into entries; only Home has more than one
@property NSArray<NSNumber *> *sectionStarts;
@property NSArray<NSDictionary *> *sectionInfo;
@end
@implementation VLCRedesignCompactBrowser

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

- (VLCLibraryModel *)model
{
    return VLCMain.sharedInstance.libraryController.libraryModel;
}

- (VLCBrowserLocation *)state
{
    return _history[_historyIndex];
}

- (NSURL *)currentFolderURL
{
    return self.state.folderURL;
}

- (void)updateAppearance
{
    _surface.layer.backgroundColor = VLCRedesignAppearance.overlayColor.CGColor;
    _rail.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    self.layer.backgroundColor = _fullLibrary ? VLCRedesignAppearance.backgroundColor.CGColor : nil;
    _sidebarCard.layer.backgroundColor = VLCRedesignAppearance.raisedColor.CGColor;
    _searchBox.layer.backgroundColor = VLCRedesignAppearance.recessedColor.CGColor;
    if (_fullLibrary)
        _divider.layer.backgroundColor = VLCRedesignAppearance.dividerColor.CGColor;
    [VLCRedesignAppearance redisplay:self];
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;

    self.wantsLayer = YES;
    _history =
        [NSMutableArray arrayWithObject:[[VLCBrowserLocation alloc] initWithSection:VLCRedesignBrowserSectionVideos
                                                                               mode:VLCBrowserModeFolders
                                                                              title:_NS("Videos")
                                                                          folderURL:nil
                                                                        libraryItem:nil]];
    _loadQueue = dispatch_queue_create("org.videolan.redesign.browser", DISPATCH_QUEUE_SERIAL);
    _artworkCache = [[NSCache alloc] init];
    _artworkCache.countLimit = 128;
    _artworkCache.totalCostLimit = 16 * 1024 * 1024;
    _pendingArtwork = [NSMutableDictionary dictionary];
    _gridMode = [NSUserDefaults.standardUserDefaults boolForKey:@"VLCRedesignCompactGrid"];
    _rawEntries = _entries = @[];
    _sectionStarts = @[ @0 ];
    _sectionInfo = @[ @{} ];
    [self setupRail];
    [self setupNavigationControls];
    [self setupSearchField];
    [self setupMediaViews];
    [self setupNotifications];
    [self updateAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateAppearance)
                                               name:VLCRedesignAppearanceChanged
                                             object:nil];
    return self;
}

#pragma mark - Setup

- (void)setFullLibrary:(BOOL)fullLibrary
{
    if (_fullLibrary == fullLibrary)
        return;
    _fullLibrary = fullLibrary;
    if (fullLibrary && !_sidebarCard) {
        _sidebarCard = [[VLCBrowserSurface alloc] init];
        _sidebarCard.wantsLayer = YES;
        _sidebarCard.layer.cornerRadius = 6;
        [self addSubview:_sidebarCard];
        NSArray *roles = @[ @"home", @"videos", @"music", @"network", @"playlists", @"recent", @"add" ];
        NSArray *names = @[
            _NS("Home"), _NS("Videos"), _NS("Music"), _NS("Network"), _NS("Playlists"), _NS("Recent"),
            _NS("Add item")
        ];
        NSMutableArray *items = [NSMutableArray array];
        __weak typeof(self) weakSelf = self;
        for (NSInteger i = 0; i < (NSInteger)roles.count; i++) {
            VLCBrowserSidebarItem *item = [[VLCBrowserSidebarItem alloc] init];
            item.role = roles[i];
            item.toolTip = item.accessibilityLabel = names[i];
            item.activate = ^{
                [weakSelf selectSection:(VLCRedesignBrowserSection)i];
            };
            [_sidebarCard addSubview:item];
            [items addObject:item];
        }
        _sidebarItems = items;
        _searchBox = [[VLCBrowserSurface alloc] init];
        _searchBox.wantsLayer = YES;
        _searchBox.layer.cornerRadius = 6;
        [self addSubview:_searchBox positioned:NSWindowBelow relativeTo:_searchField];
        _searchIcon = [[NSImageView alloc] init];
        _searchIcon.image = VLCBrowserAsset(@"search");
        [_searchBox addSubview:_searchIcon];
        /* The full library opens on Home and prefers the large grid */
        NSNumber *grid = [NSUserDefaults.standardUserDefaults objectForKey:@"VLCRedesignLibraryGrid"];
        _gridMode = grid ? grid.boolValue : YES;
        _divider.image = nil;
        _divider.wantsLayer = YES;
        [_history setArray:@[ [[VLCBrowserLocation alloc] initWithSection:VLCRedesignBrowserSectionHome
                                                                     mode:VLCBrowserModeHome
                                                                    title:_NS("Home")
                                                                folderURL:nil
                                                              libraryItem:nil] ]];
        _historyIndex = 0;
    }
    _sidebarCard.hidden = _searchBox.hidden = !fullLibrary;
    _searchField.drawsBackground = !fullLibrary;
    _rail.hidden = _surface.hidden = _expandButton.hidden = _searchButton.hidden = fullLibrary;
    _searchField.hidden = !fullLibrary && !_searchOpen;
    _searchField.placeholderString = fullLibrary ? _NS("Search") : _NS("Search media");
    _counter.alignment = fullLibrary ? NSTextAlignmentRight : NSTextAlignmentLeft;
    [self updateAppearance];
    self.needsLayout = YES;
    [self reload];
}

- (void)setGridMode:(BOOL)gridMode
{
    _gridMode = gridMode;
    _scroll.documentView = gridMode || self.state.mode == VLCBrowserModeHome ? _grid : _table;
}

- (void)showSection:(VLCRedesignBrowserSection)section
{
    [self selectSection:section];
}

- (void)setupRail
{
    _rail = [[VLCBrowserSurface alloc] init];
    _rail.wantsLayer = YES;
    [self addSubview:_rail];
    _surface = [[VLCBrowserSurface alloc] init];
    _surface.wantsLayer = YES;
    _surface.layer.cornerRadius = VLCRedesignPlayerContentRadius;
    // Only the outer corners: the inner edge continues into the video
    _surface.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    [self addSubview:_surface positioned:NSWindowBelow relativeTo:nil];
    __weak typeof(self) weakSelf = self;
    NSArray *roles = @[ @"home", @"videos", @"music", @"network", @"playlists", @"recent", @"add" ];
    NSArray *names = @[
        _NS("Home"), _NS("Videos"), _NS("Music"), _NS("Network"), _NS("Playlists"), _NS("Recent files"),
        _NS("Open media")
    ];
    NSMutableArray *rail = [NSMutableArray array];
    for (NSInteger i = 0; i < 7; i++) {
        VLCRedesignPanelButton *button = [self icon:roles[i]
                                              label:names[i]
                                             parent:_rail
                                             action:^{
                                                 [weakSelf selectSection:(VLCRedesignBrowserSection)i];
                                             }];
        [rail addObject:button];
    }
    _railButtons = rail;
}

- (void)setupNavigationControls
{
    __weak typeof(self) weakSelf = self;
    _backButton = [self icon:@"back"
                       label:_NS("Back")
                      parent:self
                      action:^{
                          [weakSelf moveHistory:-1];
                      }];
    _forwardButton = [self icon:@"forward"
                          label:_NS("Forward")
                         parent:self
                         action:^{
                             [weakSelf moveHistory:1];
                         }];
    _moreButton = [self icon:@"more"
                       label:_NS("Browser actions")
                      parent:self
                      action:^{
                          [weakSelf showActions];
                      }];
    _expandButton = [self icon:@"expand"
                         label:_NS("Open full library")
                        parent:self
                        action:^{
                            [weakSelf expand];
                        }];
    _sortButton = [self icon:@"sort"
                       label:_NS("Sort media")
                      parent:self
                      action:^{
                          [weakSelf showSort];
                      }];
    _viewButton = [[VLCBrowserModeButton alloc] init];
    _viewButton.title = @"";
    _viewButton.image = VLCBrowserAsset(@"view");
    _viewButton.toolTip = _viewButton.accessibilityLabel = _NS("View options");
    _viewButton.activate = ^{
        [weakSelf showViewOptions];
    };
    [self addSubview:_viewButton];
    _searchButton = [self icon:@"search"
                         label:_NS("Search media")
                        parent:self
                        action:^{
                            [weakSelf toggleSearch];
                        }];
    _address = [[VLCBrowserAddressButton alloc] init];
    _address.title = @"";
    _address.bordered = NO;
    _address.target = self;
    _address.action = @selector(showParents:);
    _counter = VLCBrowserLabel(14, VLCRedesignAppearance.mutedColor);
    _message = VLCBrowserLabel(14, VLCRedesignAppearance.mutedColor);
    _message.maximumNumberOfLines = 0;
    _message.lineBreakMode = NSLineBreakByWordWrapping;
    [self addSubview:_address];
    [self addSubview:_counter];
    [self addSubview:_message];
    _address.toolTip = _NS("Browse parent folders");
    _divider = [[NSImageView alloc] init];
    _divider.image = VLCBrowserAsset(@"divider");
    _divider.imageScaling = NSImageScaleNone;
    [self addSubview:_divider];
}

- (void)setupSearchField
{
    _searchField = [[NSTextField alloc] init];
    _searchField.cell = [[VLCRedesignAlignedTextFieldCell alloc] initTextCell:@""];
    _searchField.editable = YES;
    _searchField.selectable = YES;
    _searchField.usesSingleLineMode = YES;
    _searchField.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    _searchField.textColor = VLCRedesignAppearance.subduedColor;
    _searchField.backgroundColor = VLCRedesignAppearance.recessedColor;
    _searchField.drawsBackground = YES;
    _searchField.bordered = NO;
    _searchField.placeholderString = _NS("Search media");
    _searchField.accessibilityLabel = _NS("Search media");
    _searchField.delegate = self;
    _searchField.hidden = YES;
    _searchField.wantsLayer = YES;
    _searchField.layer.cornerRadius = 4;
    _searchField.layer.masksToBounds = YES;
    [self addSubview:_searchField];
}

- (void)setupMediaViews
{
    __weak typeof(self) weakSelf = self;
    _scroll = [[NSScrollView alloc] init];
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.automaticallyAdjustsContentInsets = NO;
    _scroll.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    [self addSubview:_scroll];
    _table = [[VLCBrowserTable alloc] init];
    _table.backgroundColor = NSColor.clearColor;
    _table.headerView = nil;
    _table.rowHeight = 42;
    _table.intercellSpacing = NSZeroSize;
    if (@available(macOS 11.0, *))
        _table.style = NSTableViewStylePlain;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.autoresizingMask = NSViewWidthSizable;
    [_table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"media"]];
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(activateSelected:);
    _table.activateRow = ^{
        [weakSelf activateSelected:nil];
    };
    _grid = [[VLCBrowserGrid alloc] init];
    _grid.backgroundColors = @[ NSColor.clearColor ];
    _grid.selectable = YES;
    _grid.dataSource = self;
    _grid.delegate = self;
    _gridLayout = [[NSCollectionViewFlowLayout alloc] init];
    _gridLayout.minimumInteritemSpacing = _gridLayout.minimumLineSpacing = 10;
    _grid.collectionViewLayout = _gridLayout;
    [_grid registerClass:VLCBrowserGridItem.class forItemWithIdentifier:@"media"];
    [_grid registerClass:VLCBrowserTileItem.class forItemWithIdentifier:@"tile"];
    [_grid registerClass:VLCBrowserSectionHeader.class
        forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                    withIdentifier:@"section"];
    _grid.activateItem = ^{
        [weakSelf activateSelected:nil];
    };
    NSArray *dragTypes = @[
        NSPasteboardTypeFileURL, NSPasteboardTypeURL, NSPasteboardTypeString, NSFilenamesPboardType,
        VLCMediaLibraryMediaItemUTI, VLCMediaLibraryMediaItemPasteboardType
    ];
    [_table registerForDraggedTypes:dragTypes];
    [_grid registerForDraggedTypes:dragTypes];
    [_table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    [_grid setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    _table.menu = _grid.menu = menu;
    _scroll.documentView = _gridMode ? _grid : _table;
}

- (void)setupNotifications
{
    for (NSString *name in @[
             VLCLibraryModelListOfMonitoredFoldersUpdated, VLCLibraryModelAudioMediaListReset,
             VLCLibraryModelRecentsMediaListReset, VLCLibraryModelArtistListReset, VLCLibraryModelAlbumListReset,
             VLCLibraryModelGenreListReset, VLCLibraryModelPlaylistAdded, VLCLibraryModelPlaylistUpdated,
             VLCLibraryModelPlaylistDeleted, VLCLibraryModelDiscoveryCompleted
         ])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelChanged:) name:name object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(progressChanged:)
                                               name:VLCPlayerTimeAndPositionChanged
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(closePopupNotification:)
                                               name:NSApplicationDidResignActiveNotification
                                             object:nil];
}

#pragma mark - Lifetime

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_directoryWatch)
        dispatch_source_cancel(_directoryWatch);
    if (_popupMonitor)
        [NSEvent removeMonitor:_popupMonitor];
    [_viewPopup.parentWindow removeChildWindow:_viewPopup];
    [_viewPopup orderOut:nil];
}

- (void)stopDirectoryWatch
{
    if (_directoryWatch) {
        dispatch_source_cancel(_directoryWatch);
        _directoryWatch = nil;
    }
}

- (void)suspendBrowsing
{
    ++self.generation;
    [self stopDirectoryWatch];
    [self closePopup];
}

- (void)setHidden:(BOOL)hidden
{
    if (self.hidden == hidden)
        return;
    [super setHidden:hidden];
    if (hidden)
        [self suspendBrowsing];
    else if (self.window)
        [self reload];
}

- (void)viewWillMoveToWindow:(NSWindow *)window
{
    if (!window)
        [self suspendBrowsing];
    [super viewWillMoveToWindow:window];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window && !self.hidden)
        [self reload];
}

#pragma mark - Navigation

- (VLCRedesignPanelButton *)icon:(NSString *)role
                           label:(NSString *)label
                          parent:(NSView *)parent
                          action:(void (^)(void))action
{
    VLCRedesignPanelButton *button = [[VLCRedesignPanelButton alloc] init];
    button.title = @"";
    button.image = VLCBrowserAsset(role);
    button.toolTip = button.accessibilityLabel = label;
    button.activate = action;
    [parent addSubview:button];
    return button;
}

- (void)navigate:(VLCBrowserLocation *)state
{
    [self closePopup];
    if (_historyIndex + 1 < (NSInteger)_history.count)
        [_history removeObjectsInRange:NSMakeRange(_historyIndex + 1, _history.count - _historyIndex - 1)];
    [_history addObject:state];
    if (_history.count > 64)
        [_history removeObjectAtIndex:0];
    _historyIndex = _history.count - 1;
    _searchField.stringValue = @"";
    _rawEntries = _entries = @[];
    [_table reloadData];
    [_grid reloadData];
    [_table deselectAll:nil];
    _grid.selectionIndexPaths = [NSSet set];
    [_scroll.contentView scrollToPoint:NSZeroPoint];
    [self reload];
}

- (void)browseFolder:(NSURL *)url
{
    if (!url.isFileURL)
        return;
    NSString *title = url.lastPathComponent.length ? url.lastPathComponent : @"/";
    [self navigate:[[VLCBrowserLocation alloc] initWithSection:VLCRedesignBrowserSectionVideos
                                                          mode:VLCBrowserModeDirectory
                                                         title:title
                                                     folderURL:url
                                                   libraryItem:nil]];
}

- (void)selectSection:(VLCRedesignBrowserSection)section
{
    VLCBrowserMode mode;
    NSString *title;
    switch (section) {
    case VLCRedesignBrowserSectionHome:
        if (!_fullLibrary) {
            if (self.expandLibrary)
                self.expandLibrary(nil, section, _gridMode);
            return;
        }
        mode = VLCBrowserModeHome;
        title = _NS("Home");
        break;
    case VLCRedesignBrowserSectionOpenMedia:
        [self addMedia:nil];
        return;
    case VLCRedesignBrowserSectionVideos:
        mode = VLCBrowserModeFolders;
        title = _NS("Videos");
        break;
    case VLCRedesignBrowserSectionMusic:
        mode = VLCBrowserModeMusic;
        title = _NS("Music");
        break;
    case VLCRedesignBrowserSectionNetwork:
        mode = VLCBrowserModeNetwork;
        title = _NS("Network");
        break;
    case VLCRedesignBrowserSectionPlaylists:
        mode = VLCBrowserModePlaylists;
        title = _NS("Playlists");
        break;
    case VLCRedesignBrowserSectionRecent:
        mode = VLCBrowserModeRecent;
        title = _fullLibrary ? _NS("Recent") : _NS("Recent files");
        break;
    default:
        return;
    }
    [self navigate:[[VLCBrowserLocation alloc] initWithSection:section
                                                          mode:mode
                                                         title:title
                                                     folderURL:nil
                                                   libraryItem:nil]];
}

- (void)moveHistory:(NSInteger)offset
{
    NSInteger next = _historyIndex + offset;
    if (next < 0 || next >= (NSInteger)_history.count)
        return;
    _historyIndex = next;
    _searchField.stringValue = @"";
    _rawEntries = _entries = @[];
    [_table reloadData];
    [_grid reloadData];
    [_table deselectAll:nil];
    _grid.selectionIndexPaths = [NSSet set];
    [self reload];
}

- (NSDictionary *)entryForURL:(NSURL *)url directory:(BOOL)directory
{
    NSDictionary *values = [url resourceValuesForKeys:@[ NSURLLocalizedNameKey, NSURLContentModificationDateKey ]
                                                error:nil];
    NSMutableDictionary *entry = [@{@"kind":directory ? @"folder" : @"media",@"name":values[NSURLLocalizedNameKey] ?: url.lastPathComponent ?: url.absoluteString,@"url":url,@"modified":values[NSURLContentModificationDateKey] ?: NSDate.distantPast} mutableCopy];
    if (!directory) {
        VLCMediaLibraryMediaItem *media = [VLCMediaLibraryMediaItem mediaItemForURL:url];
        if (media) {
            entry[@"played"] = @(media.playCount);
            entry[@"progress"] = @(media.progress);
        }
    }
    return entry;
}

- (NSDictionary *)entryForLibraryItem:(id<VLCMediaLibraryItemProtocol>)item kind:(NSString *)kind
{
    NSMutableDictionary *entry = [@{@"kind" : kind, @"name" : item.displayString ?: @"", @"item" : item} mutableCopy];
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        VLCMediaLibraryMediaItem *media = (VLCMediaLibraryMediaItem *)item;
        NSURL *url = [NSURL URLWithString:media.inputItem.MRL];
        if (url)
            entry[@"url"] = url;
        entry[@"played"] = @(media.playCount);
        entry[@"progress"] = @(media.progress);
        if (url.isFileURL) {
            NSDate *modified;
            [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
            if (modified)
                entry[@"modified"] = modified;
        }
    }
    return entry;
}

- (void)modelChanged:(NSNotification *)notification
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.window && !weakSelf.hidden)
            [weakSelf reload];
    });
}

- (void)reload
{
    if (!_history || !self.window || self.hidden)
        return;
    [self stopDirectoryWatch];
    VLCBrowserLocation *state = self.state;
    VLCBrowserMode mode = state.mode;
    VLCRedesignBrowserSection section = state.section;
    _address.title = state.title ?: @"";
    _address.toolTip = self.currentFolderURL.path ?: _NS("Browse parent folders");
    _backButton.enabled = _historyIndex > 0;
    _forwardButton.enabled = _historyIndex + 1 < (NSInteger)_history.count;
    NSArray *roles = @[ @"home", @"videos", @"music", @"network", @"playlists", @"recent", @"add" ];
    for (NSInteger i = 0; i < 7; i++) {
        NSString *role = roles[i];
        if (i == section && i >= 1 && i <= 4 && mode != VLCBrowserModeDirectory)
            role = [role stringByAppendingString:@"-active"];
        _railButtons[i].image = VLCBrowserAsset(role);
        _railButtons[i].needsDisplay = YES;
    }
    for (NSUInteger i = 0; i < _sidebarItems.count; i++) {
        _sidebarItems[i].chosen = (NSInteger)i == section && section != VLCRedesignBrowserSectionOpenMedia;
        _sidebarItems[i].needsDisplay = YES;
    }
    _address.crumbs = _fullLibrary ? [self breadcrumbsForLocation:state] : nil;
    _address.needsDisplay = YES;
    _scroll.documentView = _gridMode || mode == VLCBrowserModeHome ? _grid : _table;
    _counter.stringValue = _NS("Loading…");
    _message.hidden = YES;
    _loadError = nil;
    NSUInteger generation = ++self.generation;
    /* Snapshot cached library lists on the main thread. Filesystem work and
     * sorting stay on a serial background queue, with stale loads discarded. */
    NSArray *snapshot = nil;
    if (mode == VLCBrowserModeFolders)
        snapshot = self.model.listOfMonitoredFolders.copy;
    else if (mode == VLCBrowserModeSongs)
        snapshot = self.model.listOfAudioMedia.copy;
    else if (mode == VLCBrowserModeAlbums)
        snapshot = self.model.listOfAlbums.copy;
    else if (mode == VLCBrowserModeArtists)
        snapshot = self.model.listOfArtists.copy;
    else if (mode == VLCBrowserModeGenres)
        snapshot = self.model.listOfGenres.copy;
    else if (mode == VLCBrowserModeRecent)
        snapshot = self.model.listOfRecentMedia.copy;
    else if (mode == VLCBrowserModeHome)
        snapshot = @[
            self.model.listOfRecentMedia.copy ?: @[], self.model.listOfRecentAudioMedia.copy ?: @[],
            self.model.listOfMonitoredFolders.copy ?: @[]
        ];
    id<VLCMediaLibraryItemProtocol> group = state.libraryItem;
    int64_t groupID = group.libraryID;
    VLCMediaLibraryParentGroupType groupType = VLCMediaLibraryParentGroupTypeUnknown;
    if ([group isKindOfClass:VLCMediaLibraryPlaylist.class])
        groupType = VLCMediaLibraryParentGroupTypePlaylist;
    else if ([group conformsToProtocol:@protocol(VLCMediaLibraryAudioGroupProtocol)])
        groupType = ((id<VLCMediaLibraryAudioGroupProtocol>)group).matchingParentType;
    vlc_medialibrary_t *library = vlc_ml_instance_get(getIntf());
    __weak typeof(self) weakSelf = self;
    dispatch_async(_loadQueue, ^{
        typeof(self) browser = weakSelf;
        if (!browser || browser.generation != generation)
            return;
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        NSError *error = nil;
        NSArray *loadedItems = snapshot;
        if (mode == VLCBrowserModePlaylists) {
            loadedItems = VLCBrowserFetchPlaylists(library);
        } else if (mode == VLCBrowserModeGroup) {
            loadedItems = VLCBrowserFetchGroupMedia(library, groupType, groupID);
        }
        if (mode == VLCBrowserModeDirectory) {
            NSArray<NSURL *> *children = [NSFileManager.defaultManager
                  contentsOfDirectoryAtURL:state.folderURL
                includingPropertiesForKeys:@[
                    NSURLIsDirectoryKey, NSURLLocalizedNameKey, NSURLContentModificationDateKey
                ]
                                   options:NSDirectoryEnumerationSkipsHiddenFiles
                                     error:&error];
            NSSet *extensions = [NSSet setWithArray:[NSString extensionsArrayFromVLCStyleString:EXTENSIONS_MEDIA]];
            for (NSURL *url in children) {
                if (browser.generation != generation)
                    return;
                NSNumber *directory;
                [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
                if (directory.boolValue || [extensions containsObject:url.pathExtension.lowercaseString])
                    [rows addObject:[browser entryForURL:url directory:directory.boolValue]];
            }
        } else if (mode == VLCBrowserModeFolders) {
            for (VLCMediaLibraryEntryPoint *folder in snapshot) {
                NSURL *url = [NSURL URLWithString:folder.MRL];
                if (url.isFileURL && !folder.isBanned)
                    [rows addObject:[browser entryForURL:url directory:YES]];
            }
        } else if (mode == VLCBrowserModeHome) {
            [rows addObjectsFromArray:[browser homeEntriesFromSnapshot:snapshot generation:generation]];
        } else if (mode == VLCBrowserModeMusic) {
            NSArray *keys = @[ @"songs", @"albums", @"artists", @"genres" ],
                    *names = @[ _NS("Songs"), _NS("Albums"), _NS("Artists"), _NS("Genres") ];
            const VLCBrowserMode modes[] = {VLCBrowserModeSongs, VLCBrowserModeAlbums, VLCBrowserModeArtists,
                                            VLCBrowserModeGenres};
            for (NSUInteger i = 0; i < keys.count; i++)
                [rows addObject:@{@"kind" : @"category", @"mode" : @(modes[i]), @"name" : names[i], @"icon" : keys[i]}];
        } else if (mode == VLCBrowserModeNetwork) {
            for (VLCMediaSource *source in [VLCMediaSourceProvider listOfMediaSourcesForCategory:SD_CAT_INTERNET])
                [rows addObject:@{
                    @"kind" : @"source",
                    @"name" : source.mediaSourceDescription ?: @"",
                    @"source" : source,
                    @"icon" : @"network"
                }];
        } else {
            BOOL groups = VLCBrowserModeShowsGroups(mode);
            for (id<VLCMediaLibraryItemProtocol> item in loadedItems) {
                if (browser.generation != generation)
                    return;
                NSMutableDictionary *entry = [[browser entryForLibraryItem:item
                                                                      kind:mode == VLCBrowserModePlaylists ? @"playlist"
                                                                           : groups                        ? @"group"
                                                                                    : @"media"] mutableCopy];
                if (groups)
                    entry[@"icon"] = VLCBrowserGroupIcon(mode);
                [rows addObject:entry];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.generation != generation || !strongSelf.window || strongSelf.hidden)
                return;
            strongSelf.rawEntries = rows;
            strongSelf.loadError = error.localizedDescription;
            [strongSelf applyFilter];
            if (mode == VLCBrowserModeDirectory && !strongSelf.hidden)
                [strongSelf watchFolder:state.folderURL];
        });
    });
}

/* Home shows what the library knows: unfinished and recent videos, recently
 * played audio and the folders the library monitors. */
- (NSArray<NSDictionary *> *)homeEntriesFromSnapshot:(NSArray *)snapshot generation:(NSUInteger)generation
{
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger count = 0;
    for (VLCMediaLibraryMediaItem *media in snapshot[0]) {
        if (self.generation != generation)
            return @[];
        if (media.mediaType != VLC_ML_MEDIA_TYPE_VIDEO)
            continue;
        NSMutableDictionary *entry = [[self entryForLibraryItem:media kind:@"media"] mutableCopy];
        entry[@"section"] = @"continue";
        [rows addObject:entry];
        if (++count == 12)
            break;
    }
    count = 0;
    for (VLCMediaLibraryMediaItem *media in snapshot[1]) {
        NSMutableDictionary *entry = [[self entryForLibraryItem:media kind:@"media"] mutableCopy];
        entry[@"section"] = @"listen";
        entry[@"subtitle"] = media.primaryDetailString ?: @"";
        [rows addObject:entry];
        if (++count == 12)
            break;
    }
    for (VLCMediaLibraryEntryPoint *folder in snapshot[2]) {
        NSURL *url = [NSURL URLWithString:folder.MRL];
        if (!url.isFileURL || folder.isBanned)
            continue;
        NSMutableDictionary *entry = [[self entryForURL:url directory:YES] mutableCopy];
        entry[@"section"] = @"folders";
        [rows addObject:entry];
    }
    return rows;
}

- (NSArray<NSString *> *)breadcrumbsForLocation:(VLCBrowserLocation *)state
{
    NSArray *sections = @[ _NS("Home"), _NS("Videos"), _NS("Music"), _NS("Network"), _NS("Playlists"), _NS("Recent") ];
    NSString *root = state.section < (NSInteger)sections.count ? sections[state.section] : state.title;
    if (state.mode != VLCBrowserModeDirectory)
        return [state.title isEqualToString:root] || !state.title.length ? @[ root ] : @[ root, state.title ];
    /* Folders inside a monitored library folder show the path from that folder. */
    NSString *path = state.folderURL.path.stringByStandardizingPath;
    NSString *base = nil;
    for (VLCMediaLibraryEntryPoint *folder in self.model.listOfMonitoredFolders) {
        NSString *candidate = [NSURL URLWithString:folder.MRL].path.stringByStandardizingPath;
        if (candidate.length && [path hasPrefix:candidate] && candidate.length > base.length)
            base = candidate;
    }
    NSArray *components = base ? [@[ base.lastPathComponent ]
                                     arrayByAddingObjectsFromArray:[path substringFromIndex:base.length].pathComponents]
                               : path.pathComponents;
    NSMutableArray *crumbs = [NSMutableArray arrayWithObject:root];
    for (NSString *component in components)
        if (component.length && ![component isEqualToString:@"/"])
            [crumbs addObject:component];
    if (!base && crumbs.count > 4)
        [crumbs replaceObjectsInRange:NSMakeRange(1, crumbs.count - 4) withObjectsFromArray:@[ @"…" ]];
    return crumbs;
}

- (void)watchFolder:(NSURL *)url
{
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_loadQueue, ^{
        /* Opening a watch descriptor may block for a mounted/network folder. */
        int descriptor = open(url.fileSystemRepresentation, O_EVTONLY | O_CLOEXEC);
        if (descriptor < 0)
            return;
        dispatch_source_t watcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, descriptor,
                                                           DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE |
                                                               DISPATCH_VNODE_RENAME | DISPATCH_VNODE_ATTRIB,
                                                           dispatch_get_main_queue());
        if (!watcher) {
            close(descriptor);
            return;
        }
        dispatch_source_set_cancel_handler(watcher, ^{
            close(descriptor);
        });
        dispatch_source_set_event_handler(watcher, ^{
            typeof(self) browser = weakSelf;
            if (browser && browser.generation == generation && browser.window && !browser.hidden)
                [browser reload];
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) browser = weakSelf;
            if (!browser || browser.generation != generation || !browser.window || browser.hidden) {
                dispatch_source_cancel(watcher);
                return;
            }
            [browser stopDirectoryWatch];
            browser.directoryWatch = watcher;
        });
        dispatch_resume(watcher);
    });
}

#pragma mark - Filtering and actions

- (void)applyFilter
{
    NSString *query = _searchField.stringValue;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in _rawEntries)
        if (!query.length || [entry[@"name"] localizedStandardContainsString:query])
            [rows addObject:entry];
    VLCBrowserSortMode sortMode = _sortMode;
    VLCBrowserMode mode = self.state.mode;
    _sortButton.enabled = mode != VLCBrowserModeMusic && mode != VLCBrowserModeHome;
    if (mode != VLCBrowserModeMusic && mode != VLCBrowserModeHome)
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            if ([a[@"kind"] isEqualToString:@"folder"] != [b[@"kind"] isEqualToString:@"folder"])
                return [a[@"kind"] isEqualToString:@"folder"] ? NSOrderedAscending : NSOrderedDescending;
            if (sortMode == VLCBrowserSortModificationDate) {
                NSComparisonResult result =
                    [(b[@"modified"] ?: NSDate.distantPast) compare:(a[@"modified"] ?: NSDate.distantPast)];
                if (result != NSOrderedSame)
                    return result;
            }
            if (sortMode == VLCBrowserSortUnwatchedFirst || sortMode == VLCBrowserSortWatchedFirst) {
                NSInteger playedA = [a[@"played"] integerValue] > 0, playedB = [b[@"played"] integerValue] > 0;
                if (playedA != playedB)
                    return (playedA < playedB) == (sortMode == VLCBrowserSortUnwatchedFirst) ? NSOrderedAscending
                                                                                             : NSOrderedDescending;
            }
            NSComparisonResult result = [a[@"name"] localizedStandardCompare:b[@"name"]];
            return sortMode == VLCBrowserSortNameDescending ? -result : result;
        }];
    NSUInteger total = rows.count;
    if (mode == VLCBrowserModeHome && !query.length)
        total = MAX(rows.count, self.model.numberOfVideoMedia + self.model.numberOfAudioMedia);
    _counter.stringValue = total == 1 ? _NS("1 item") : [NSString stringWithFormat:_NS("%lu items"), total];
    BOOL canAdd = VLCBrowserModeAllowsAdding(mode);
    if (canAdd && !query.length)
        [rows insertObject:@{
            @"kind" : @"add",
            @"name" : mode == VLCBrowserModeNetwork ? _NS("Add Network Stream")
            : mode == VLCBrowserModePlaylists       ? _NS("Create playlist")
                                                    : _NS("Add"),
            @"icon" : @"add"
        }
                   atIndex:0];
    _entries = rows;
    [self buildSections];
    [_table reloadData];
    [_grid reloadData];
    ((VLCBrowserModeButton *)_viewButton).gridIcon = _gridMode;
    _viewButton.needsDisplay = YES;
    _message.hidden = rows.count > (canAdd && !query.length ? 1 : 0) || (!query.length && canAdd);
    _message.stringValue = _loadError ?: (query.length ? _NS("No matching media") : _NS("No media here yet"));
    if (_loadError.length)
        _message.hidden = NO;
    self.needsLayout = YES;
}

- (void)buildSections
{
    if (self.state.mode != VLCBrowserModeHome) {
        _sectionStarts = @[ @0 ];
        _sectionInfo = @[ @{} ];
        return;
    }
    NSDictionary *titles = @{
        @"continue" : _NS("Continue Watching"),
        @"listen" : _NS("Listen Again"),
        @"folders" : _NS("Frequently Visited Folders")
    };
    NSDictionary *styles = @{
        @"continue" : @(VLCBrowserTileVideo),
        @"listen" : @(VLCBrowserTileSquare),
        @"folders" : @(VLCBrowserTileFolder)
    };
    NSDictionary *targets = @{
        @"continue" : @(VLCRedesignBrowserSectionRecent),
        @"listen" : @(VLCRedesignBrowserSectionMusic),
        @"folders" : @(VLCRedesignBrowserSectionVideos)
    };
    NSMutableArray *starts = [NSMutableArray array], *info = [NSMutableArray array];
    NSString *current = nil;
    for (NSUInteger i = 0; i < _entries.count; i++) {
        NSString *key = _entries[i][@"section"];
        if ([key isEqualToString:current])
            continue;
        current = key;
        [starts addObject:@(i)];
        [info addObject:@{@"title" : titles[key] ?: @"", @"style" : styles[key] ?: @0, @"target" : targets[key] ?: @0}];
    }
    _sectionStarts = starts.count ? starts : @[ @0 ];
    _sectionInfo = info.count ? info : @[ @{} ];
}

- (NSInteger)entryIndexForPath:(NSIndexPath *)path
{
    if (path.section < 0 || path.section >= (NSInteger)_sectionStarts.count)
        return -1;
    NSInteger index = _sectionStarts[path.section].integerValue + path.item;
    return index < (NSInteger)_entries.count ? index : -1;
}

- (NSInteger)countForSection:(NSInteger)section
{
    if (section < 0 || section >= (NSInteger)_sectionStarts.count)
        return 0;
    NSInteger end = section + 1 < (NSInteger)_sectionStarts.count ? _sectionStarts[section + 1].integerValue
                                                                   : (NSInteger)_entries.count;
    return MAX(0, end - _sectionStarts[section].integerValue);
}

- (VLCBrowserTileStyle)tileStyleForPath:(NSIndexPath *)path
{
    if (self.state.mode == VLCBrowserModeHome)
        return (VLCBrowserTileStyle)[_sectionInfo[path.section][@"style"] integerValue];
    return VLCBrowserTileVideo;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    [self applyFilter];
}

- (void)toggleSearch
{
    [self closePopup];
    _searchOpen = !_searchOpen;
    _searchField.hidden = !_searchOpen;
    _counter.hidden = _sortButton.hidden = _viewButton.hidden = _searchOpen;
    if (_searchOpen)
        [self.window makeFirstResponder:_searchField];
    else {
        _searchField.stringValue = @"";
        [self applyFilter];
    }
    self.needsLayout = YES;
}

- (NSInteger)selectedIndex
{
    if (_scroll.documentView == _grid)
        return _grid.selectionIndexPaths.anyObject ? [self entryIndexForPath:_grid.selectionIndexPaths.anyObject] : -1;
    return _table.selectedRow;
}

- (void)activateSelected:(id)sender
{
    NSInteger index = self.selectedIndex;
    if (index >= 0 && index < (NSInteger)_entries.count)
        [self activateEntry:_entries[index]];
}

- (void)activateEntry:(NSDictionary *)entry
{
    NSString *kind = entry[@"kind"];
    if ([kind isEqualToString:@"add"]) {
        [self addMedia:nil];
    } else if ([kind isEqualToString:@"folder"]) {
        [self browseFolder:entry[@"url"]];
    } else if ([kind isEqualToString:@"category"]) {
        [self navigate:[[VLCBrowserLocation alloc] initWithSection:VLCRedesignBrowserSectionMusic
                                                              mode:(VLCBrowserMode)[entry[@"mode"] integerValue]
                                                             title:entry[@"name"]
                                                         folderURL:nil
                                                       libraryItem:nil]];
    } else if ([kind isEqualToString:@"group"] || [kind isEqualToString:@"playlist"]) {
        [self navigate:[[VLCBrowserLocation alloc] initWithSection:self.state.section
                                                              mode:VLCBrowserModeGroup
                                                             title:entry[@"name"]
                                                         folderURL:nil
                                                       libraryItem:entry[@"item"]]];
    } else if ([kind isEqualToString:@"source"]) {
        if (self.openNetworkSource)
            self.openNetworkSource(entry[@"source"]);
    } else {
        [self enqueueEntry:entry play:YES];
    }
}

- (void)enqueueEntry:(NSDictionary *)entry play:(BOOL)play
{
    id<VLCMediaLibraryItemProtocol> item = entry[@"item"];
    if (item) {
        [VLCMain.sharedInstance.libraryController appendItemsToPlayQueue:item.mediaItems playFirstItemImmediately:play];
        return;
    }
    NSURL *url = entry[@"url"];
    if (!url)
        return;
    VLCOpenInputMetadata *metadata = [[VLCOpenInputMetadata alloc] init];
    metadata.MRLString = url.absoluteString;
    [self.queue addPlayQueueItems:@[ metadata ] atPosition:NSUIntegerMax startPlayback:play];
}

- (VLCMediaLibraryPlaylist *)currentPlaylist
{
    id item = self.state.libraryItem;
    return [item isKindOfClass:VLCMediaLibraryPlaylist.class] ? item : nil;
}

- (BOOL)appendMetadataToPlaylist:(NSArray<VLCOpenInputMetadata *> *)metadata
{
    VLCMediaLibraryPlaylist *playlist = [self currentPlaylist];
    if (!playlist || playlist.readOnly)
        return NO;
    NSMutableArray *items = [NSMutableArray array];
    for (VLCOpenInputMetadata *entry in metadata) {
        NSURL *url = [NSURL URLWithString:entry.MRLString];
        VLCMediaLibraryMediaItem *item = [VLCMediaLibraryMediaItem mediaItemForURL:url]
                                             ?: [[VLCMediaLibraryMediaItem alloc] initWithExternalURL:url];
        if (item)
            [items addObject:item];
    }
    BOOL result = [playlist appendMediaItems:items];
    if (result)
        [self reload];
    return result;
}

- (void)addMedia:(id)sender
{
    VLCBrowserMode mode = self.state.mode;
    if (mode == VLCBrowserModeNetwork) {
        [VLCMain.sharedInstance.open openNet];
        return;
    }
    if (mode == VLCBrowserModePlaylists) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Create playlist");
        [alert addButtonWithTitle:_NS("Create")];
        [alert addButtonWithTitle:_NS("Cancel")];
        NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 28)];
        name.cell = [[VLCRedesignAlignedTextFieldCell alloc] initTextCell:@""];
        name.editable = YES;
        name.selectable = YES;
        name.usesSingleLineMode = YES;
        name.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
        name.placeholderString = _NS("Playlist name");
        alert.accessoryView = name;
        [alert beginSheetModalForWindow:self.window
                      completionHandler:^(NSModalResponse response) {
                          NSString *title = [name.stringValue
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                          if (response != NSAlertFirstButtonReturn || !title.length)
                              return;
                          vlc_medialibrary_t *library = vlc_ml_instance_get(getIntf());
                          if (!library)
                              return;
                          vlc_ml_playlist_t *playlist = vlc_ml_playlist_create(library, title.UTF8String);
                          if (playlist)
                              vlc_ml_playlist_release(playlist);
                          else
                              NSBeep();
                          [self reload];
                      }];
        return;
    }
    NSOpenPanel *picker = NSOpenPanel.openPanel;
    picker.canChooseDirectories = ![self currentPlaylist];
    picker.canChooseFiles = (mode != VLCBrowserModeFolders && mode != VLCBrowserModeMusic);
    picker.allowsMultipleSelection = YES;
    [picker beginSheetModalForWindow:self.window
                   completionHandler:^(NSModalResponse response) {
                       if (response != NSModalResponseOK)
                           return;
                       NSMutableArray *metadata = [NSMutableArray array];
                       for (NSURL *url in picker.URLs) {
                           NSNumber *directory;
                           [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
                           if (directory.boolValue)
                               [VLCMain.sharedInstance.libraryController addFolderWithFileURL:url];
                           else
                               [metadata addObject:[VLCOpenInputMetadata inputMetaWithPath:url.path]];
                       }
                       if (metadata.count) {
                           if ([self currentPlaylist]) {
                               if (![self appendMetadataToPlaylist:metadata])
                                   NSBeep();
                           } else
                               [self.queue addPlayQueueItems:metadata atPosition:NSUIntegerMax startPlayback:NO];
                       }
                       [self reload];
                   }];
}

- (void)expand
{
    [self closePopup];
    if (self.expandLibrary)
        self.expandLibrary(self.currentFolderURL, self.state.section, _gridMode);
}

- (void)showParents:(id)sender
{
    NSString *path = self.currentFolderURL.path.stringByStandardizingPath;
    if (!path.length)
        return;
    NSMenu *menu = [[NSMenu alloc] init];
    while (path.length) {
        NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
        NSMenuItem *item = [menu addItemWithTitle:[path isEqualToString:@"/"] ? @"/" : path.lastPathComponent
                                           action:@selector(openParent:)
                                    keyEquivalent:@""];
        item.target = self;
        item.representedObject = url;
        if ([path isEqualToString:@"/"])
            break;
        NSString *parent = path.stringByDeletingLastPathComponent;
        if (parent.length >= path.length)
            break;
        path = parent;
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 24) inView:_address];
}

- (void)openParent:(NSMenuItem *)sender
{
    [self browseFolder:sender.representedObject];
}

- (void)showSort
{
    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    BOOL hasDate = NO, hasWatchedState = NO;
    for (NSDictionary *entry in _rawEntries) {
        hasDate |= entry[@"modified"] != nil;
        hasWatchedState |= entry[@"played"] != nil;
    }
    NSArray *names =
        @[ _NS("Name (A–Z)"), _NS("Name (Z–A)"), _NS("Date modified"), _NS("Unwatched first"), _NS("Watched first") ];
    for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
        NSMenuItem *item = [menu addItemWithTitle:names[i] action:@selector(sort:) keyEquivalent:@""];
        item.target = self;
        item.tag = i;
        item.state = i == _sortMode ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = i < 2 || (i == 2 ? hasDate : hasWatchedState);
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 24) inView:_sortButton];
}

- (void)sort:(NSMenuItem *)sender
{
    _sortMode = (VLCBrowserSortMode)sender.tag;
    [self applyFilter];
}

- (void)showActions
{
    NSMenu *menu = [[NSMenu alloc] init];
    for (NSArray *entry in @[
             @[ _NS("Add media…"), NSStringFromSelector(@selector(addMedia:)) ],
             @[ _NS("Refresh"), NSStringFromSelector(@selector(refresh:)) ],
             @[ _NS("Browse parent folders"), NSStringFromSelector(@selector(showParents:)) ],
             @[ _NS("Open full library"), NSStringFromSelector(@selector(expand:)) ]
         ]) {
        NSMenuItem *item = [menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
        item.target = self;
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 24) inView:_moreButton];
}

- (void)refresh:(id)sender
{
    [self reload];
}

- (void)expand:(id)sender
{
    [self expand];
}

- (void)showViewOptions
{
    if (_viewPopup) {
        [self closePopup];
        return;
    }
    VLCBrowserSurface *content = [[VLCBrowserSurface alloc] initWithFrame:NSMakeRect(0, 0, 265, 104)];
    content.wantsLayer = YES;
    content.layer.cornerRadius = 10;
    content.layer.backgroundColor = [VLCRedesignAppearance.raisedColor colorWithAlphaComponent:.95].CGColor;
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < 2; i++) {
        VLCBrowserViewOption *button = [[VLCBrowserViewOption alloc] init];
        button.frame = NSMakeRect(4, 4 + i * 48, 257, 48);
        button.gridIcon = i == 0;
        button.chosen = _gridMode == (i == 0);
        button.title = i == 0 ? _NS("Grid View") : _NS("List View");
        button.accessibilityLabel = button.title;
        button.activate = ^{
            weakSelf.gridMode = i == 0;
            [NSUserDefaults.standardUserDefaults setBool:weakSelf.gridMode
                                                  forKey:weakSelf.fullLibrary ? @"VLCRedesignLibraryGrid"
                                                                              : @"VLCRedesignCompactGrid"];
            [weakSelf closePopup];
            weakSelf.scroll.documentView = weakSelf.gridMode ? weakSelf.grid : weakSelf.table;
            [weakSelf applyFilter];
        };
        [content addSubview:button];
    }
    _viewPopup =
        [[VLCBrowserPopup alloc] initWithContentRect:content.bounds
                                           styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
    _viewPopup.contentView = content;
    _viewPopup.backgroundColor = NSColor.clearColor;
    _viewPopup.opaque = NO;
    _viewPopup.hasShadow = YES;
    _viewPopup.releasedWhenClosed = NO;
    _viewPopup.hidesOnDeactivate = YES;
    NSRect anchor = [self.window convertRectToScreen:[_viewButton convertRect:_viewButton.bounds toView:nil]];
    NSRect screen = self.window.screen.visibleFrame;
    CGFloat x = MAX(NSMinX(screen), MIN(NSMaxX(anchor) - 265, NSMaxX(screen) - 265));
    [_viewPopup setFrameOrigin:NSMakePoint(x, MAX(NSMinY(screen), NSMinY(anchor) - 110))];
    [self.window addChildWindow:_viewPopup ordered:NSWindowAbove];
    [_viewPopup makeKeyAndOrderFront:nil];
    _popupMonitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskKeyDown
                                     handler:^NSEvent *(NSEvent *event) {
                                         typeof(self) browser = weakSelf;
                                         if (!browser)
                                             return event;
                                         if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
                                             [browser closePopup];
                                             return nil;
                                         }
                                         if (event.type == NSEventTypeLeftMouseDown &&
                                             event.window != browser.viewPopup) {
                                             NSPoint point = [browser.viewButton convertPoint:event.locationInWindow
                                                                                     fromView:nil];
                                             if (event.window != browser.window ||
                                                 !NSPointInRect(point, browser.viewButton.bounds))
                                                 [browser closePopup];
                                         }
                                         return event;
                                     }];
}

- (void)closePopupNotification:(NSNotification *)notification
{
    [self closePopup];
}

- (void)closePopup
{
    NSWindow *parent = _viewPopup.parentWindow;
    [parent removeChildWindow:_viewPopup];
    [_viewPopup orderOut:nil];
    _viewPopup = nil;
    if (_popupMonitor) {
        [NSEvent removeMonitor:_popupMonitor];
        _popupMonitor = nil;
    }
    if (parent.visible && NSApp.active)
        [parent makeKeyWindow];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _entries.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    return [[VLCBrowserRow alloc] init];
}

- (void)configureArtwork:(VLCBrowserArtwork *)artwork
                   entry:(NSDictionary *)entry
                   large:(BOOL)large
                 changed:(void (^)(NSImage *))changed
{
    NSString *icon = entry[@"icon"];
    if (!icon && [entry[@"kind"] isEqualToString:@"folder"])
        icon = @"folder";
    if (!icon && [entry[@"kind"] isEqualToString:@"playlist"])
        icon = @"playlists";
    artwork.intrinsicAsset = icon.length > 0;
    artwork.image = icon.length ? VLCBrowserAsset(icon) : nil;
    artwork.progress = [entry[@"progress"] doubleValue];
    artwork.needsDisplay = YES;
    if (icon.length)
        return;
    NSURL *url = entry[@"url"];
    if (!url.isFileURL)
        return;
    NSDate *modified = entry[@"modified"];
    NSString *key = [NSString stringWithFormat:@"%@:%f:%d", url.absoluteString, modified.timeIntervalSince1970, large];
    NSImage *cached = [_artworkCache objectForKey:key];
    if (cached) {
        artwork.image = cached;
        return;
    }
    if (_pendingArtwork[key]) {
        if (changed)
            [_pendingArtwork[key] addObject:[changed copy]];
        return;
    }
    _pendingArtwork[key] = [NSMutableArray array];
    if (changed)
        [_pendingArtwork[key] addObject:[changed copy]];
    VLCInputItem *input = [VLCInputItem inputItemFromURL:url];
    __weak typeof(self) weakSelf = self;
    [input thumbnailWithSize:large ? NSMakeSize(320, 180) : NSMakeSize(64, 64)
           completionHandler:^(NSImage *image) {
               dispatch_async(dispatch_get_main_queue(), ^{
                   typeof(self) browser = weakSelf;
                   if (!browser)
                       return;
                   NSArray *callbacks = browser.pendingArtwork[key].copy;
                   [browser.pendingArtwork removeObjectForKey:key];
                   if (image)
                       [browser.artworkCache setObject:image
                                                forKey:key
                                                  cost:(NSUInteger)(large ? 320 * 180 * 4 : 64 * 64 * 4)];
                   for (void (^callback)(NSImage *) in callbacks)
                       callback(image);
               });
           }];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    VLCBrowserCell *cell = [tableView makeViewWithIdentifier:@"browser-media" owner:self];
    if (!cell) {
        cell = [[VLCBrowserCell alloc] init];
        cell.identifier = @"browser-media";
    }
    NSDictionary *entry = _entries[row];
    NSURL *url = entry[@"url"];
    cell.representedURL = url;
    cell.representedEntry = entry;
    cell.textField.stringValue = entry[@"name"];
    cell.textField.toolTip = entry[@"name"];
    __weak VLCBrowserCell *weakCell = cell;
    [self configureArtwork:cell.artwork
                     entry:entry
                     large:NO
                   changed:^(NSImage *image) {
                       if (weakCell.representedEntry == entry) {
                           weakCell.artwork.image = image;
                           weakCell.artwork.needsDisplay = YES;
                       }
                   }];
    return cell;
}

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return _sectionStarts.count;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self countForSection:section];
}

- (NSView *)collectionView:(NSCollectionView *)collectionView
    viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
                          atIndexPath:(NSIndexPath *)indexPath
{
    VLCBrowserSectionHeader *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                   withIdentifier:@"section"
                                                                     forIndexPath:indexPath];
    NSDictionary *info = _sectionInfo[indexPath.section];
    header.title = info[@"title"];
    __weak typeof(self) weakSelf = self;
    VLCRedesignBrowserSection target = (VLCRedesignBrowserSection)[info[@"target"] integerValue];
    header.activate = ^{
        [weakSelf selectSection:target];
    };
    header.needsDisplay = YES;
    return header;
}

- (NSSize)collectionView:(NSCollectionView *)collectionView
                      layout:(NSCollectionViewLayout *)layout
    referenceSizeForHeaderInSection:(NSInteger)section
{
    if (![_sectionInfo[section][@"title"] length])
        return NSZeroSize;
    return NSMakeSize(NSWidth(collectionView.bounds), 24);
}

- (NSEdgeInsets)collectionView:(NSCollectionView *)collectionView
                        layout:(NSCollectionViewLayout *)layout
        insetForSectionAtIndex:(NSInteger)section
{
    if (!_fullLibrary)
        return NSEdgeInsetsMake(0, 0, 0, 0);
    /* Home sections: 20 pt between a heading and its tiles, 40 pt before the next heading */
    BOOL titled = [_sectionInfo[section][@"title"] length] > 0;
    return NSEdgeInsetsMake(titled ? 20 : 0, 0, titled ? 40 : 0, 0);
}

- (NSSize)collectionView:(NSCollectionView *)collectionView
                    layout:(NSCollectionViewLayout *)layout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!_fullLibrary)
        return _gridLayout.itemSize;
    VLCBrowserTileStyle style = [self tileStyleForPath:indexPath];
    if (style == VLCBrowserTileVideo)
        return _gridLayout.itemSize;
    CGFloat lines = style == VLCBrowserTileSquare ? 2 : 1;
    return NSMakeSize(200, 200 + VLCBrowserTileCaptionGap + lines * VLCBrowserTileLineHeight + (lines - 1) * 10);
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger index = [self entryIndexForPath:indexPath];
    NSDictionary *entry = index >= 0 ? _entries[index] : @{};
    if (_fullLibrary)
        return [self tileForEntry:entry style:[self tileStyleForPath:indexPath] indexPath:indexPath];
    VLCBrowserGridItem *item = [collectionView makeItemWithIdentifier:@"media" forIndexPath:indexPath];
    NSURL *url = entry[@"url"];
    item.representedURL = url;
    item.representedEntry = entry;
    item.textField.stringValue = entry[@"name"];
    item.textField.toolTip = entry[@"name"];
    __weak typeof(self) weakSelf = self;
    __weak VLCBrowserGridItem *weakItem = item;
    item.activate = ^{
        [weakSelf activateEntry:entry];
    };
    [self configureArtwork:item.artwork
                     entry:entry
                     large:YES
                   changed:^(NSImage *image) {
                       if (weakItem.representedEntry == entry) {
                           weakItem.artwork.image = image;
                           weakItem.artwork.needsDisplay = YES;
                       }
                   }];
    return item;
}

- (NSCollectionViewItem *)tileForEntry:(NSDictionary *)entry
                                 style:(VLCBrowserTileStyle)style
                             indexPath:(NSIndexPath *)indexPath
{
    VLCBrowserTileItem *item = [_grid makeItemWithIdentifier:@"tile" forIndexPath:indexPath];
    VLCBrowserTileView *tile = item.tile;
    item.representedURL = entry[@"url"];
    item.representedEntry = entry;
    tile.style = style;
    tile.title.stringValue = entry[@"name"] ?: @"";
    tile.title.toolTip = entry[@"name"];
    tile.subtitle.stringValue = entry[@"subtitle"] ?: @"";
    /* Finished media keeps a full progress line and a dimmed caption, as in the reference */
    BOOL watched = [entry[@"played"] integerValue] > 0 && [entry[@"progress"] doubleValue] <= 0;
    tile.title.textColor = watched ? VLCRedesignAppearance.mutedColor : VLCRedesignAppearance.subduedColor;
    tile.needsLayout = YES;
    __weak typeof(self) weakSelf = self;
    __weak VLCBrowserTileItem *weakItem = item;
    item.activate = ^{
        [weakSelf activateEntry:entry];
    };
    VLCBrowserArtwork *artwork = tile.artwork;
    [self configureArtwork:artwork
                     entry:entry
                     large:YES
                   changed:^(NSImage *image) {
                       if (weakItem.representedEntry == entry) {
                           weakItem.tile.artwork.image = image;
                           weakItem.tile.artwork.needsDisplay = YES;
                       }
                   }];
    if (watched)
        artwork.progress = 1;
    artwork.iconSize = artwork.intrinsicAsset ? 48 : 0;
    artwork.fillColor = artwork.intrinsicAsset ? VLCRedesignAppearance.raisedColor : nil;
    return item;
}

- (id<NSPasteboardWriting>)pasteboardForEntry:(NSDictionary *)entry
{
    id<VLCMediaLibraryItemProtocol> libraryItem = entry[@"item"];
    if (libraryItem)
        return [NSPasteboardItem pasteboardItemWithLibraryItem:libraryItem];
    NSURL *url = entry[@"url"];
    return url; /* NSURL provides modern native file-URL/URL drag types. */
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    return [self pasteboardForEntry:_entries[row]];
}

- (id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView
       pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger index = [self entryIndexForPath:indexPath];
    return index >= 0 ? [self pasteboardForEntry:_entries[index]] : nil;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView
    canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
                   withEvent:(NSEvent *)event
{
    for (NSIndexPath *path in indexPaths) {
        NSInteger index = [self entryIndexForPath:path];
        if (index >= 0 && (_entries[index][@"url"] || _entries[index][@"item"]))
            return YES;
    }
    return NO;
}

- (BOOL)acceptPasteboard:(NSPasteboard *)pasteboard
{
    /* Library drags preserve their IDs; file/URL drops explicitly enqueue and
     * never inherit the open-file autoplay preference. */
    if ([pasteboard availableTypeFromArray:@[ VLCMediaLibraryMediaItemUTI, VLCMediaLibraryMediaItemPasteboardType ]]) {
        VLCMediaLibraryPlaylist *playlist = [self currentPlaylist];
        if (!playlist)
            return [VLCFileDragRecognisingView handlePasteboardFromDragSessionAsPlayQueueItems:pasteboard];
        NSMutableArray *items = [NSMutableArray array];
        for (NSPasteboardItem *entry in pasteboard.pasteboardItems) {
            NSData *data = [entry dataForType:VLCMediaLibraryMediaItemPasteboardType]
                               ?: [entry dataForType:VLCMediaLibraryMediaItemUTI];
            if (data)
                [items addObjectsFromArray:[VLCMediaLibraryMediaItem mediaItemsFromPasteboardData:data] ?: @[]];
        }
        BOOL result = [playlist appendMediaItems:items];
        if (result)
            [self reload];
        return result;
    }
    NSArray *metadata = [VLCFileDragRecognisingView inputMetadataFromPasteboard:pasteboard];
    if (!metadata.count)
        return NO;
    if ([self currentPlaylist])
        return [self appendMetadataToPlaylist:metadata];
    [self.queue addPlayQueueItems:metadata atPosition:NSUIntegerMax startPlayback:NO];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    return info.draggingSource == tableView ? NSDragOperationNone : NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
    return [self acceptPasteboard:info.draggingPasteboard];
}

- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
                     validateDrop:(id<NSDraggingInfo>)info
                proposedIndexPath:(NSIndexPath *_Nonnull *_Nonnull)indexPath
                    dropOperation:(NSCollectionViewDropOperation *)operation
{
    return info.draggingSource == collectionView ? NSDragOperationNone : NSDragOperationCopy;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView
            acceptDrop:(id<NSDraggingInfo>)info
             indexPath:(NSIndexPath *)indexPath
         dropOperation:(NSCollectionViewDropOperation)operation
{
    return [self acceptPasteboard:info.draggingPasteboard];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    if (_scroll.documentView == _grid) {
        NSPoint point = [_grid convertPoint:NSApp.currentEvent.locationInWindow fromView:nil];
        NSIndexPath *path = [_grid indexPathForItemAtPoint:point];
        if (path)
            _grid.selectionIndexPaths = [NSSet setWithObject:path];
    }
    if (_scroll.documentView == _table && _table.clickedRow >= 0)
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:_table.clickedRow] byExtendingSelection:NO];
    NSInteger index = self.selectedIndex;
    if (index < 0 || index >= (NSInteger)_entries.count)
        return;
    NSDictionary *entry = _entries[index];
    NSString *kind = entry[@"kind"];
    NSMenuItem *open =
        [menu addItemWithTitle:[@[ @"folder", @"playlist", @"group", @"category", @"source" ] containsObject:kind]
                                   ? _NS("Open")
                                   : _NS("Play")
                        action:@selector(activateSelected:)
                 keyEquivalent:@""];
    open.target = self;
    if (entry[@"url"] || entry[@"item"]) {
        NSMenuItem *enqueue = [menu addItemWithTitle:_NS("Add to queue")
                                              action:@selector(enqueueSelected:)
                                       keyEquivalent:@""];
        enqueue.target = self;
    }
    if (((NSURL *)entry[@"url"]).isFileURL) {
        NSMenuItem *reveal = [menu addItemWithTitle:_NS("Show in Finder")
                                             action:@selector(revealSelected:)
                                      keyEquivalent:@""];
        reveal.target = self;
    }
    if ([kind isEqualToString:@"playlist"]) {
        NSMenuItem *rename = [menu addItemWithTitle:_NS("Rename…") action:@selector(renamePlaylist:) keyEquivalent:@""];
        rename.target = self;
    }
}

- (void)enqueueSelected:(id)sender
{
    NSInteger index = self.selectedIndex;
    if (index >= 0 && index < (NSInteger)_entries.count)
        [self enqueueEntry:_entries[index] play:NO];
}

- (void)revealSelected:(id)sender
{
    NSInteger index = self.selectedIndex;
    if (index >= 0 && index < (NSInteger)_entries.count) {
        NSURL *url = _entries[index][@"url"];
        if (url.isFileURL)
            [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ url ]];
    }
}

- (void)renamePlaylist:(id)sender
{
    NSInteger index = self.selectedIndex;
    if (index < 0 || index >= (NSInteger)_entries.count)
        return;
    VLCMediaLibraryPlaylist *playlist = _entries[index][@"item"];
    if ([playlist isKindOfClass:VLCMediaLibraryPlaylist.class]) {
        [VLCMain.sharedInstance.libraryController showRenamePlaylistDialogForPlaylist:playlist];
        [self reload];
    }
}

- (void)progressChanged:(NSNotification *)notification
{
    if (!self.window || self.hidden)
        return;
    NSURL *url = self.queue.playerController.URLOfCurrentMediaItem;
    CGFloat progress = self.queue.playerController.position;
    if (!url)
        return;
    if (_scroll.documentView == _grid)
        for (VLCBrowserGridItem *item in _grid.visibleItems) {
            if ([item.representedURL isEqual:url]) {
                item.artwork.progress = progress;
                item.artwork.needsDisplay = YES;
            }
        }
    else {
        NSRange range = [_table rowsInRect:_table.visibleRect];
        for (NSUInteger row = range.location; row < NSMaxRange(range) && row < _entries.count; row++) {
            VLCBrowserCell *cell = [_table viewAtColumn:0 row:row makeIfNecessary:NO];
            if ([cell.representedURL isEqual:url]) {
                cell.artwork.progress = progress;
                cell.artwork.needsDisplay = YES;
            }
        }
    }
}

/* Figma 970:4028 at 1920 pt: a 217 pt sidebar column holding an inset card,
 * then a 20 pt padded content area. Narrow windows keep an icon-only sidebar. */
- (void)layoutFullLibrary
{
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
    BOOL iconOnly = width < 760;
    CGFloat sidebar = iconOnly ? 62 : 217;
    _sidebarCard.frame = NSMakeRect(8, 8, sidebar - 16, MAX(0, height - 16));
    for (NSUInteger i = 0; i < _sidebarItems.count; i++) {
        VLCBrowserSidebarItem *item = _sidebarItems[i];
        item.iconOnly = iconOnly;
        item.frame = iconOnly ? NSMakeRect(7, 12 + i * 46, 32, 32)
                              : NSMakeRect(16, 12 + i * 46, NSWidth(_sidebarCard.frame) - 32, 32);
        item.needsDisplay = YES;
    }
    CGFloat left = sidebar + 20, right = width - 20, top = 20, row = 32;
    _backButton.frame = NSMakeRect(left, top + 4, 24, 24);
    _forwardButton.frame = NSMakeRect(left + 36, top + 4, 24, 24);
    _moreButton.frame = NSMakeRect(right - 24, top + 4, 24, 24);
    CGFloat searchWidth = MIN(325, MAX(120, (right - left) * .28));
    _searchBox.frame = NSMakeRect(NSMinX(_moreButton.frame) - 20 - searchWidth, top, searchWidth, row);
    _searchIcon.frame = NSMakeRect(8, 4, 24, 24);
    _searchField.frame = NSMakeRect(NSMinX(_searchBox.frame) + 42, top + 4, MAX(0, searchWidth - 50), 24);
    _viewButton.frame = NSMakeRect(NSMinX(_searchBox.frame) - 20 - 24, top + 4, 24, 24);
    _sortButton.frame = NSMakeRect(NSMinX(_viewButton.frame) - 20 - 24, top + 4, 24, 24);
    BOOL roomForCount = NSMinX(_sortButton.frame) - (left + 72) > 260;
    _counter.hidden = !roomForCount;
    _counter.frame = NSMakeRect(NSMinX(_sortButton.frame) - 20 - 110, top + 4, 110, 24);
    CGFloat crumbsEnd = roomForCount ? NSMinX(_counter.frame) - 10 : NSMinX(_sortButton.frame) - 20;
    _address.frame = NSMakeRect(left + 72, top + 4, MAX(0, crumbsEnd - left - 72), 24);
    _divider.frame = NSMakeRect(left, top + row + 17, MAX(0, right - left), 1);
    CGFloat bodyTop = NSMaxY(_divider.frame);
    _scroll.frame = NSMakeRect(left, bodyTop, MAX(0, right - left), MAX(0, height - bodyTop));
    _scroll.contentInsets = NSEdgeInsetsMake(20, 0, 20, 0);
    [_scroll tile];
    CGFloat bodyWidth = NSWidth(_scroll.contentView.bounds);
    /* As many columns as fit at the reference 316 pt tile width, tiles filling the row */
    NSUInteger columns = MAX(1, (NSUInteger)ceil((bodyWidth + 20) / (316 + 20)));
    CGFloat itemWidth = floor(MAX(0, (bodyWidth - (columns - 1) * 20) / columns));
    _gridLayout.minimumInteritemSpacing = 20;
    _gridLayout.minimumLineSpacing = 40;
    _gridLayout.itemSize =
        NSMakeSize(itemWidth, floor(itemWidth * 9. / 16.) + VLCBrowserTileCaptionGap + VLCBrowserTileLineHeight);
    /* Sections have varying tile sizes, so measure the laid-out content at this width */
    [_grid setFrameSize:NSMakeSize(bodyWidth, NSHeight(_grid.frame))];
    [_gridLayout invalidateLayout];
    [_grid layoutSubtreeIfNeeded];
    [_grid setFrameSize:NSMakeSize(bodyWidth, MAX(_gridLayout.collectionViewContentSize.height,
                                                  NSHeight(_scroll.contentView.bounds)))];
    _table.frame = NSMakeRect(0, 0, bodyWidth, MAX(NSHeight(_scroll.contentView.bounds), _entries.count * 42));
    _table.tableColumns.firstObject.width = bodyWidth;
    _message.frame = NSMakeRect(left, bodyTop + 20, MAX(0, right - left), 80);
}

- (void)layout
{
    [super layout];
    if (_fullLibrary) {
        [self layoutFullLibrary];
        return;
    }
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds), content = MAX(0, width - 90);
    _rail.frame = NSMakeRect(0, 0, 50, height);
    _surface.frame = NSMakeRect(50, 0, MAX(0, width - 50), height);
    for (NSUInteger i = 0; i < _railButtons.count; i++)
        _railButtons[i].frame = NSMakeRect(10, 8 + i * 46, 30, 32);
    _backButton.frame = NSMakeRect(70, 20, 24, 24);
    _forwardButton.frame = NSMakeRect(106, 20, 24, 24);
    _address.frame = NSMakeRect(140, 20, MAX(0, width - 240), 24);
    _moreButton.frame = NSMakeRect(width - 80, 20, 24, 24);
    _expandButton.frame = NSMakeRect(width - 44, 20, 24, 24);
    _counter.frame = NSMakeRect(70, 64, MAX(0, content - 108), 24);
    _sortButton.frame = NSMakeRect(width - 116, 64, 24, 24);
    _viewButton.frame = NSMakeRect(width - 80, 64, 24, 24);
    _searchButton.frame = NSMakeRect(width - 44, 64, 24, 24);
    _searchField.frame = NSMakeRect(70, 60, MAX(0, width - 126), 32);
    _divider.frame = NSMakeRect(70, 104, content, 1);
    _scroll.frame = NSMakeRect(70, 125, content, MAX(0, height - 145));
    [_scroll tile];
    CGFloat bodyWidth = NSWidth(_scroll.contentView.bounds);
    if (_gridMode) {
        NSUInteger columns = bodyWidth >= 300 ? 2 : 1;
        CGFloat itemWidth = MAX(0, (bodyWidth - (columns - 1) * 10) / columns);
        _gridLayout.itemSize = NSMakeSize(itemWidth, itemWidth * 9. / 16. + 46);
        NSUInteger rows = (_entries.count + columns - 1) / columns;
        CGFloat contentHeight = rows ? rows * _gridLayout.itemSize.height + (rows - 1) * 10 : 0;
        _grid.frame = NSMakeRect(0, 0, bodyWidth, MAX(contentHeight, NSHeight(_scroll.contentView.bounds)));
    } else {
        _table.frame = NSMakeRect(0, 0, bodyWidth, MAX(NSHeight(_scroll.contentView.bounds), _entries.count * 42));
        _table.tableColumns.firstObject.width = bodyWidth;
    }
    _message.frame = NSMakeRect(70, 125, content, 80);
}

@end
