/*****************************************************************************
 * subtitle-controls.m: native color entry and subtitle size-mode checks
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>

@protocol SubtitleColorTest <NSObject>
- (instancetype)initWithTitle:(NSString *)title;
@property uint32_t RGB;
@property BOOL enabled;
@property (copy) void (^changed)(uint32_t);
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (void)colorChanged:(NSColorWell *)well;
@end

@protocol SubtitleModeTest <NSObject>
@property BOOL pixelMode;
@property (copy) void (^changed)(BOOL);
@end

static BOOL Check(BOOL condition, const char *description)
{
    fprintf(stderr, "%s: %s\n", description, condition ? "PASS" : "FAIL");
    return condition;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 2)
            return 1;
        [NSApplication sharedApplication];
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "%s\n", dlerror());
            return 1;
        }
        NSView<SubtitleColorTest> *row = (id)[(id<SubtitleColorTest>)[NSClassFromString(@"VLCRedesignColorRow") alloc]
            initWithTitle:@"Text Color"];
        NSTextField *field = [row valueForKey:@"field"];
        NSColorWell *well = [row valueForKey:@"well"];
        __block NSUInteger calls = 0;
        __block uint32_t applied = 0;
        row.changed = ^(uint32_t value) { calls++; applied = value; };
        NSNotification *edited = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field];
        field.stringValue = @"#12AbEf";
        [(id<SubtitleColorTest>)row controlTextDidEndEditing:edited];
        BOOL passed = Check(applied == 0x12ABEF && [field.stringValue isEqualToString:@"#12ABEF"],
                            "Valid RGB entry applies and normalizes");
        for (NSString *invalid in @[@"#FFF", @"#GGGGGG", @"FF00AA trailing", @""]) {
            field.stringValue = invalid;
            [(id<SubtitleColorTest>)row controlTextDidEndEditing:edited];
        }
        passed &= Check(calls == 1 && row.RGB == 0x12ABEF, "Malformed colors do not reach the binding");
        row.RGB = 0x334455;
        passed &= Check(calls == 1, "Refreshing the color does not send a user action");
        well.color = NSColor.yellowColor;
        [row colorChanged:well];
        passed &= Check(applied == 0xFFFF00 && calls == 2, "Native color choice reaches the RGB binding");
        row.enabled = NO;
        field.stringValue = @"#FFFFFF";
        [(id<SubtitleColorTest>)row controlTextDidEndEditing:edited];
        [row colorChanged:well];
        passed &= Check(!field.enabled && !well.enabled && calls == 2,
                        "Disabled controls cannot change the value");
        row.enabled = YES;
        passed &= Check(field.alignment == NSTextAlignmentCenter, "Color input text is centered");
        for (NSNumber *width in @[@400, @320, @240]) {
            row.frame = NSMakeRect(0, 0, width.doubleValue, 48);
            [row layoutSubtreeIfNeeded];
            passed &= Check(NSContainsRect(row.bounds, field.frame) && NSContainsRect(row.bounds, well.frame) &&
                            NSMaxX(field.frame) < NSMinX(well.frame), "Color field and swatch fit without overlap");
        }
        NSView<SubtitleModeTest> *mode = (id)[[NSClassFromString(@"VLCRedesignSizeModeRow") alloc] init];
        NSSegmentedControl *segments = [mode valueForKey:@"segments"];
        __block NSUInteger modeCalls = 0;
        __block BOOL pixels = NO;
        mode.changed = ^(BOOL value) { modeCalls++; pixels = value; };
        segments.selectedSegment = 1;
        [segments sendAction:segments.action to:segments.target];
        passed &= Check(pixels && mode.pixelMode && modeCalls == 1, "Pixel selection reaches its binding");
        mode.pixelMode = NO;
        passed &= Check(segments.selectedSegment == 0 && modeCalls == 1,
                        "Refresh selects Relative without emitting an edit");
        return passed ? 0 : 1;
    }
}
