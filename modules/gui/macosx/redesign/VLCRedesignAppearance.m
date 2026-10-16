/*****************************************************************************
 * VLCRedesignAppearance.m: Appearance roles for the desktop redesign
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignAppearance.h"
#import <CoreText/CoreText.h>

NSNotificationName const VLCRedesignAppearanceChanged = @"VLCRedesignAppearanceChanged";
static NSString * const VLCThemeKey = @"VLCRedesignTheme";
static NSString * const VLCAccentKey = @"VLCRedesignAccentIndex";

@implementation VLCRedesignAppearance

+ (NSString *)theme
{
    NSString *theme = [NSUserDefaults.standardUserDefaults stringForKey:VLCThemeKey];
    return [@[@"dark", @"light", @"system"] containsObject:theme] ? theme : @"dark";
}

+ (void)setTheme:(NSString *)theme
{
    if (![@[@"dark", @"light", @"system"] containsObject:theme])
        return;
    [NSUserDefaults.standardUserDefaults setObject:theme forKey:VLCThemeKey];
    [self apply];
}

+ (NSInteger)accentIndex
{
    return MAX(0, MIN(8, [NSUserDefaults.standardUserDefaults integerForKey:VLCAccentKey]));
}

+ (void)setAccentIndex:(NSInteger)index
{
    [NSUserDefaults.standardUserDefaults setInteger:MAX(0, MIN(8, index)) forKey:VLCAccentKey];
    [self apply];
}

+ (BOOL)dark
{
    if ([self.theme isEqualToString:@"system"]) {
        if (@available(macOS 10.14, *)) {
            NSString *name = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
                             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            return [name isEqualToString:NSAppearanceNameDarkAqua];
        }
        return NO;
    }
    return [self.theme isEqualToString:@"dark"];
}

+ (NSColor *)colorWithRGB:(NSUInteger)rgb
{
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.
                             green:((rgb >> 8) & 0xff) / 255.
                              blue:(rgb & 0xff) / 255.
                             alpha:1.];
}

+ (NSColor *)backgroundColor { return [self colorWithRGB:self.dark ? 0x0e0e0e : 0xe7e7e7]; }
+ (NSColor *)recessedColor { return [self colorWithRGB:self.dark ? 0x090909 : 0xdedede]; }
+ (NSColor *)panelColor { return [self colorWithRGB:self.dark ? 0x1b1b1b : 0xd5d5d5]; }
+ (NSColor *)foregroundColor { return [self colorWithRGB:self.dark ? 0xeaeaea : 0x161616]; }
+ (NSColor *)secondaryColor { return [self colorWithRGB:self.dark ? 0xc6c6c6 : 0x2e2e2e]; }
+ (NSColor *)subduedColor { return [self colorWithRGB:self.dark ? 0x969696 : 0x515151]; }
+ (NSColor *)borderColor { return [self colorWithRGB:self.dark ? 0x373737 : 0x9b9b9b]; }

+ (NSColor *)accentColor
{
    const NSUInteger colors[] = {0xd37918, 0xe15032, 0xc49e23, 0x19a234, 0x18aad3,
                                 0x185dd3, 0x8e42ff, 0xf052b3, 0xafafaf};
    if (self.accentIndex == 0 && !self.dark)
        return [self colorWithRGB:0xe8851a];
    return [self colorWithRGB:colors[self.accentIndex]];
}

+ (void)registerFonts
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *weight in @[@"Light", @"Regular", @"Medium", @"SemiBold"]) {
            NSURL *url = [NSBundle.mainBundle URLForResource:[@"Inter-" stringByAppendingString:weight]
                                             withExtension:@"ttf"];
            if (url)
                CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
        }
    });
}

+ (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight
{
    [self registerFonts];
    NSString *name = weight <= NSFontWeightLight ? @"Inter-Light" :
                     weight >= NSFontWeightSemibold ? @"Inter-SemiBold" :
                     weight >= NSFontWeightMedium ? @"Inter-Medium" : @"Inter-Regular";
    return [NSFont fontWithName:name size:size] ?: [NSFont systemFontOfSize:size weight:weight];
}

+ (void)apply
{
    [self registerFonts];
    if (@available(macOS 10.14, *)) {
        NSApp.appearance = [self.theme isEqualToString:@"system"] ? nil :
            [NSAppearance appearanceNamed:self.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:VLCRedesignAppearanceChanged object:nil];
}

@end
