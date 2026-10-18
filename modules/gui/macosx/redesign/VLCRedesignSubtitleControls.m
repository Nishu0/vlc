/*****************************************************************************
 * Native typography and color controls for subtitle appearance
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignSubtitleControls.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"
#include <stdlib.h>

static VLCRedesignAlignedLabel *AppearanceLabel(NSString *title)
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:title];
    label.font = [VLCRedesignAppearance fontOfSize:13 weight:NSFontWeightRegular];
    label.textColor = [VLCRedesignAppearance colorWithRGB:0x969696];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static NSRect AppearanceControlFrame(NSView *view)
{
    CGFloat width = NSWidth(view.bounds);
    CGFloat controlWidth = MIN(188, MAX(112, width * .47));
    return NSMakeRect(MAX(0, width - controlWidth - 20), 10, controlWidth, 28);
}

@interface VLCRedesignColorRow ()
@property VLCRedesignAlignedLabel *label;
@property NSTextField *field;
@property NSColorWell *well;
@end

@implementation VLCRedesignColorRow

- (BOOL)isFlipped { return YES; }

- (instancetype)initWithTitle:(NSString *)title
{
    self = [super initWithFrame:NSMakeRect(0, 0, 400, 48)];
    if (!self)
        return nil;
    _label = AppearanceLabel(title);
    [self addSubview:_label];
    _field = [[NSTextField alloc] init];
    _field.cell = [[VLCRedesignAlignedTextFieldCell alloc] initTextCell:@""];
    _field.font = [VLCRedesignAppearance fontOfSize:12 weight:NSFontWeightRegular];
    _field.textColor = [VLCRedesignAppearance colorWithRGB:0xBBBBBB];
    _field.backgroundColor = NSColor.blackColor;
    _field.bordered = NO;
    _field.drawsBackground = YES;
    _field.editable = YES;
    _field.selectable = YES;
    _field.alignment = NSTextAlignmentCenter;
    _field.delegate = self;
    _field.accessibilityLabel = title;
    _field.toolTip = _NS("Enter a six-digit color, such as #FFFFFF.");
    _field.wantsLayer = YES;
    _field.layer.cornerRadius = 4;
    _field.layer.masksToBounds = YES;
    [self addSubview:_field];
    _well = [[NSColorWell alloc] init];
    if (@available(macOS 13.0, *))
        _well.colorWellStyle = NSColorWellStyleMinimal;
    _well.accessibilityLabel = [NSString stringWithFormat:_NS("Choose %@"), title];
    _well.target = self;
    _well.action = @selector(colorChanged:);
    [self addSubview:_well];
    self.enabled = YES;
    self.RGB = 0xFFFFFF;
    return self;
}

- (void)layout
{
    [super layout];
    NSRect control = AppearanceControlFrame(self);
    _label.frame = NSMakeRect(20, 0, MAX(0, NSMinX(control) - 32), 48);
    _field.frame = NSMakeRect(NSMinX(control), 10, NSWidth(control) - 36, 28);
    _well.frame = NSMakeRect(NSMaxX(control) - 28, 10, 28, 28);
}

- (void)setRGB:(uint32_t)RGB
{
    _RGB = RGB & 0xFFFFFF;
    if (!_field.currentEditor)
        _field.stringValue = [NSString stringWithFormat:@"#%06X", _RGB];
    _well.color = [VLCRedesignAppearance colorWithRGB:_RGB];
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    _field.enabled = enabled;
    _well.enabled = enabled;
    if (!enabled)
        [_well deactivate];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSString *text = [_field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([text hasPrefix:@"#"])
        text = [text substringFromIndex:1];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    BOOL valid = text.length == 6 && [text rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound;
    if (valid && self.enabled) {
        self.RGB = (uint32_t)strtoul(text.UTF8String, NULL, 16);
        if (self.changed)
            self.changed(self.RGB);
    }
    _field.stringValue = [NSString stringWithFormat:@"#%06X", self.RGB];
}

- (void)colorChanged:(NSColorWell *)sender
{
    NSColor *color = [sender.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!color || !self.enabled)
        return;
    self.RGB = ((uint32_t)lround(color.redComponent * 255) << 16) |
               ((uint32_t)lround(color.greenComponent * 255) << 8) |
               (uint32_t)lround(color.blueComponent * 255);
    if (self.changed)
        self.changed(self.RGB);
}

- (void)viewWillMoveToWindow:(NSWindow *)window
{
    if (!window)
        [_well deactivate];
    [super viewWillMoveToWindow:window];
}

@end

@interface VLCSubtitleSizeModeCell : NSSegmentedCell
@end
@implementation VLCSubtitleSizeModeCell
- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(NSView *)view
{
    BOOL selected = [self isSelectedForSegment:segment];
    NSColor *background = selected ? [VLCRedesignAppearance.accentColor colorWithAlphaComponent:.25]
                                    : [VLCRedesignAppearance colorWithRGB:0x090909];
    [background setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 1, 0) xRadius:4 yRadius:4] fill];
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:[self labelForSegment:segment]
        attributes:@{ NSFontAttributeName : [VLCRedesignAppearance fontOfSize:12 weight:NSFontWeightRegular],
                      NSForegroundColorAttributeName : selected ? VLCRedesignAppearance.accentColor
                                                                : [VLCRedesignAppearance colorWithRGB:0x969696] }];
    VLCDrawAlignedText(title, NSInsetRect(frame, 6, 0), view.flipped, NSTextAlignmentCenter);
    if (view.window.firstResponder == view) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 1, 1) xRadius:4 yRadius:4] stroke];
    }
}
@end

@interface VLCRedesignSizeModeRow ()
@property VLCRedesignAlignedLabel *label;
@property NSSegmentedControl *segments;
@end
@implementation VLCRedesignSizeModeRow
- (BOOL)isFlipped { return YES; }
- (instancetype)init
{
    self = [super initWithFrame:NSMakeRect(0, 0, 400, 48)];
    if (!self)
        return nil;
    _label = AppearanceLabel(_NS("Font Size"));
    [self addSubview:_label];
    _segments = [[NSSegmentedControl alloc] init];
    _segments.cell = [[VLCSubtitleSizeModeCell alloc] init];
    _segments.segmentCount = 2;
    [_segments setLabel:_NS("Relative") forSegment:0];
    [_segments setLabel:_NS("Pixels") forSegment:1];
    _segments.selectedSegment = 0;
    _segments.accessibilityLabel = _NS("Subtitle size mode");
    _segments.target = self;
    _segments.action = @selector(modeChanged:);
    [self addSubview:_segments];
    return self;
}
- (void)layout
{
    [super layout];
    NSRect control = AppearanceControlFrame(self);
    _label.frame = NSMakeRect(20, 0, MAX(0, NSMinX(control) - 32), 48);
    _segments.frame = control;
    for (NSInteger i = 0; i < 2; i++)
        [_segments setWidth:NSWidth(control) / 2 forSegment:i];
}
- (void)setPixelMode:(BOOL)pixelMode
{
    _pixelMode = pixelMode;
    _segments.selectedSegment = pixelMode ? 1 : 0;
}
- (void)modeChanged:(NSSegmentedControl *)sender
{
    self.pixelMode = sender.selectedSegment == 1;
    if (self.changed)
        self.changed(self.pixelMode);
}
@end
