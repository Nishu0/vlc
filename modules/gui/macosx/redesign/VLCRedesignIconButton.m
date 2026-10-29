/*****************************************************************************
 * VLCRedesignIconButton.m: Icon buttons shared by the redesigned player and library
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignIconButton.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignPanelButton.h"

NSImage *VLCPlayerAsset(NSString *role)
{
    NSString *name =
        [NSString stringWithFormat:@"VLC-redesign-player-%@-%@", VLCRedesignAppearance.dark ? @"dark" : @"light", role];
    return VLCRedesignPanelImage(name);
}

@implementation VLCPlayerIconButton

- (void)drawRect:(NSRect)dirtyRect
{
    BOOL hasActiveIcon = [@[ @"queue", @"audio", @"subtitles", @"settings", @"sidebar" ] containsObject:self.assetRole];
    if (self.transport || self.highlighted || (self.selected && !hasActiveIcon)) {
        NSColor *color = self.transport ? (self.playing ? VLCRedesignAppearance.mutedColor
                                                        : VLCRedesignAppearance.accentColor)
                                        : VLCRedesignAppearance.borderColor;
        [color setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds
                                         xRadius:self.transport ? 6 : 4
                                         yRadius:self.transport ? 6 : 4] fill];
    }
    NSImage *image =
        self.selected && hasActiveIcon
            ? VLCRedesignPanelImage([@"VLC-redesign-player-active-" stringByAppendingString:self.assetRole])
            : self.image;
    if (self.playing && self.transport)
        image = VLCRedesignPanelImage(@"VLC-redesign-player-pause");
    NSSize size = image.size;
    NSRect slot = NSMakeRect(floor(NSMidX(self.bounds) - size.width / 2), floor(NSMidY(self.bounds) - size.height / 2),
                             size.width, size.height);
    [image drawInRect:slot
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:self.enabled ? 1 : .35
        respectFlipped:YES
                 hints:nil];
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1)
                                                             xRadius:4
                                                             yRadius:4];
        ring.lineWidth = 2;
        [ring stroke];
    }
}

- (NSEdgeInsets)alignmentRectInsets
{
    return NSEdgeInsetsMake(0, 0, 0, 0);
}

@end
