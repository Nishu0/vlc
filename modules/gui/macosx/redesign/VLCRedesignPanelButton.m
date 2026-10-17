/*****************************************************************************
 * Native controls shared by the redesigned player panels
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import "VLCRedesignPanelButton.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"

NSImage *VLCRedesignPanelImage(NSString *name)
{
    static NSCache<NSString *, NSImage *> *cache;
    static NSSet<NSString *> *reflectedAssets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 256;
        /* These exports omit the enclosing horizontal reflection. Keep the
         * original SVGs, but restore their displayed orientation once here so
         * every caller, theme and selected state uses the same geometry. */
        reflectedAssets = [NSSet setWithArray:@[
            @"VLC-redesign-player-dark-sidebar", @"VLC-redesign-player-light-sidebar",
            @"VLC-redesign-player-active-sidebar", @"VLC-redesign-player-dark-folder",
            @"VLC-redesign-player-light-folder", @"VLC-redesign-player-dark-speaker",
            @"VLC-redesign-player-light-speaker", @"VLC-redesign-tracks-video-off",
            @"VLC-redesign-tracks-video-on", @"VLC-redesign-tracks-refresh",
            @"VLC-redesign-queue-repeat", @"VLC-redesign-queue-shuffle",
            @"VLC-redesign-browser-videos", @"VLC-redesign-browser-videos-active",
            @"VLC-redesign-browser-music", @"VLC-redesign-browser-music-active",
            @"VLC-redesign-browser-recent", @"VLC-redesign-browser-folder",
            @"VLC-redesign-browser-back", @"VLC-redesign-browser-forward",
            @"VLC-redesign-browser-expand", @"VLC-redesign-browser-songs",
            @"VLC-redesign-browser-albums"
        ]];
    });
    NSImage *image = [cache objectForKey:name];
    if (!image) {
        NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"svg"];
        if (!path)
            return nil;
        image = [[NSImage alloc] initWithContentsOfFile:path];
        if (image && [reflectedAssets containsObject:name]) {
            NSImage *source = image;
            image = [NSImage imageWithSize:source.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
                [NSGraphicsContext saveGraphicsState];
                NSAffineTransform *reflection = [NSAffineTransform transform];
                [reflection translateXBy:NSMinX(rect) + NSMaxX(rect) yBy:0];
                [reflection scaleXBy:-1 yBy:1];
                [reflection concat];
                [source drawInRect:rect
                          fromRect:NSZeroRect
                         operation:NSCompositingOperationSourceOver
                          fraction:1
                    respectFlipped:YES
                             hints:nil];
                [NSGraphicsContext restoreGraphicsState];
                return YES;
            }];
        }
        if (image)
            [cache setObject:image forKey:name];
    }
    return image;
}

@implementation VLCRedesignPanelButton

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

- (NSAccessibilityRole)accessibilityRole
{
    return self.selectionImage ? NSAccessibilityRadioButtonRole : NSAccessibilityButtonRole;
}

- (id)accessibilityValue
{
    return self.selectionImage || self.tab || self.highlightedSelection ? @(self.state == NSControlStateValueOn) : nil;
}

- (NSEdgeInsets)alignmentRectInsets
{
    return NSEdgeInsetsMake(0, 0, 0, 0);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    if (self.footer || self.highlighted || (self.highlightedSelection && self.state == NSControlStateValueOn)) {
        [[VLCRedesignAppearance colorWithRGB:self.highlighted ? 0x222222 : 0x090909] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:4 yRadius:4] fill];
    }
    NSColor *color =
        [VLCRedesignAppearance colorWithRGB:self.tab      ? (self.state == NSControlStateValueOn ? 0x8F8F8F : 0x6B6B6B)
                                            : self.footer ? 0x6B6B6B
                                                          : 0x969696];
    NSFont *font = [VLCRedesignAppearance fontOfSize:self.tab ? 12 : 14 weight:NSFontWeightRegular];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:self.title
                                                               attributes:@{
                                                                   NSFontAttributeName : font,
                                                                   NSForegroundColorAttributeName : color,
                                                                   NSParagraphStyleAttributeName : paragraph
                                                               }];
    NSRect textSlot = self.footer ? bounds : NSMakeRect(42, 0, MAX(0, NSWidth(bounds) - 46), NSHeight(bounds));
    if (self.tab) {
        CGFloat groupWidth = MIN(text.size.width, NSWidth(bounds) - 40) + 28;
        CGFloat x = floor((NSWidth(bounds) - groupWidth) / 2);
        [self.image drawInRect:NSMakeRect(x, 14, 20, 20)
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1
                respectFlipped:YES
                         hints:nil];
        textSlot = NSMakeRect(x + 28, 14, MAX(0, groupWidth - 28), 20);
        NSImage *line = self.underlineImage;
        [NSGraphicsContext saveGraphicsState];
        NSRectClip(NSMakeRect(8, 48, MAX(0, NSWidth(bounds) - 16), 2));
        [line drawInRect:NSMakeRect((NSWidth(bounds) - line.size.width) / 2, 48, line.size.width, line.size.height)
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1
            respectFlipped:YES
                     hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    } else if (self.selectionImage && self.state == NSControlStateValueOn) {
        [self.selectionImage drawInRect:NSMakeRect(4, (NSHeight(bounds) - 24) / 2, 24, 24)
                               fromRect:NSZeroRect
                              operation:NSCompositingOperationSourceOver
                               fraction:1
                         respectFlipped:YES
                                  hints:nil];
    } else if (self.image) {
        NSSize size = self.image.size;
        [self.image drawInRect:NSMakeRect((NSWidth(bounds) - size.width) / 2, (NSHeight(bounds) - size.height) / 2,
                                          size.width, size.height)
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1
                respectFlipped:YES
                         hints:nil];
    }
    VLCDrawAlignedText(text, textSlot, self.flipped,
                       self.tab || self.footer ? NSTextAlignmentCenter : NSTextAlignmentLeft);
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, 1) xRadius:4 yRadius:4] stroke];
    }
}

@end
