/*****************************************************************************
 * VLCRedesignAppearance.m: Appearance roles for the desktop redesign
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignAppearance.h"
#import <CoreText/CoreText.h>

NSNotificationName const VLCRedesignAppearanceChanged = @"VLCRedesignAppearanceChanged";
const CGFloat VLCRedesignPlayerContentRadius = 7;
static NSString *const VLCThemeKey = @"VLCRedesignTheme";
static NSString *const VLCAccentKey = @"VLCRedesignAccentIndex";

// Follows macOS appearance changes while the "system" theme is selected
@interface VLCRedesignSystemAppearanceObserver : NSObject
@end

@implementation VLCRedesignSystemAppearanceObserver

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (![VLCRedesignAppearance.theme isEqualToString:@"system"])
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:VLCRedesignAppearanceChanged object:nil];
    });
}

@end

@implementation VLCRedesignAppearance

+ (NSString *)theme
{
    NSString *theme = [NSUserDefaults.standardUserDefaults stringForKey:VLCThemeKey];
    return [@[ @"dark", @"light", @"system" ] containsObject:theme] ? theme : @"dark";
}

+ (void)setTheme:(NSString *)theme
{
    if (![@[ @"dark", @"light", @"system" ] containsObject:theme])
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
            NSString *name = [NSApp.effectiveAppearance
                bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
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

+ (NSAppearance *)themeAppearance
{
    if (@available(macOS 10.14, *))
        return [NSAppearance appearanceNamed:self.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    return [NSAppearance appearanceNamed:self.dark ? NSAppearanceNameVibrantDark : NSAppearanceNameAqua];
}

+ (BOOL)appearanceIsDark:(NSAppearance *)appearance
{
    if (@available(macOS 10.14, *)) {
        NSString *name =
            [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
        return [name isEqualToString:NSAppearanceNameDarkAqua];
    }
    return self.dark;
}

+ (NSColor *)colorWithDark:(NSUInteger)dark light:(NSUInteger)light
{
    if (@available(macOS 10.15, *)) {
        return [NSColor colorWithName:nil
                      dynamicProvider:^NSColor *(NSAppearance *appearance) {
                          return [self colorWithRGB:[self appearanceIsDark:appearance] ? dark : light];
                      }];
    }
    return [self colorWithRGB:self.dark ? dark : light];
}

+ (NSColor *)backgroundColor
{
    return [self colorWithDark:0x0e0e0e light:0xe7e7e7];
}

+ (NSColor *)recessedColor
{
    return [self colorWithDark:0x090909 light:0xdedede];
}

+ (NSColor *)panelColor
{
    return [self colorWithDark:0x1b1b1b light:0xd5d5d5];
}

+ (NSColor *)foregroundColor
{
    return [self colorWithDark:0xeaeaea light:0x161616];
}

+ (NSColor *)secondaryColor
{
    return [self colorWithDark:0xc6c6c6 light:0x2e2e2e];
}

+ (NSColor *)subduedColor
{
    return [self colorWithDark:0x969696 light:0x515151];
}

+ (NSColor *)borderColor
{
    return [self colorWithDark:0x373737 light:0x9b9b9b];
}

+ (NSColor *)mutedColor
{
    return [self colorWithDark:0x6b6b6b light:0x7a7a7a];
}

+ (NSColor *)dividerColor
{
    return [self colorWithDark:0x222222 light:0xacacac];
}

+ (NSColor *)hoverColor
{
    return [self colorWithDark:0x303030 light:0xc8c8c8];
}

+ (NSColor *)raisedColor
{
    return [self colorWithDark:0x191919 light:0xd5d5d5];
}

+ (NSColor *)overlayColor
{
    // The design's 95% fill relies on a backdrop blur; without one the video shows
    // through, while the reference video shows a solid panel
    return self.backgroundColor;
}

+ (NSColor *)accentColorForDark:(BOOL)dark
{
    const NSUInteger colors[] = {0xd37918, 0xe15032, 0xc49e23, 0x19a234, 0x18aad3,
                                 0x185dd3, 0x8e42ff, 0xf052b3, 0xafafaf};
    if (self.accentIndex == 0 && !dark)
        return [self colorWithRGB:0xe8851a];
    return [self colorWithRGB:colors[self.accentIndex]];
}

+ (NSColor *)accentColor
{
    if (@available(macOS 10.15, *)) {
        return [NSColor colorWithName:nil
                      dynamicProvider:^NSColor *(NSAppearance *appearance) {
                          return [self accentColorForDark:[self appearanceIsDark:appearance]];
                      }];
    }
    return [self accentColorForDark:self.dark];
}

+ (NSColor *)accentBackingColor
{
    // Dark #371F06 and light #D8BA9A for the default orange, following other accents
    NSColor * (^backing)(BOOL) = ^NSColor *(BOOL dark) {
        NSColor *background = [self colorWithRGB:dark ? 0x0e0e0e : 0xe7e7e7];
        return [[self accentColorForDark:dark] blendedColorWithFraction:dark ? .79 : .6 ofColor:background];
    };
    if (@available(macOS 10.15, *)) {
        return [NSColor colorWithName:nil
                      dynamicProvider:^NSColor *(NSAppearance *appearance) {
                          return backing([self appearanceIsDark:appearance]);
                      }];
    }
    return backing(self.dark);
}

+ (void)registerFonts
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *weight in @[ @"Light", @"Regular", @"Medium", @"SemiBold" ]) {
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
    NSString *name = weight <= NSFontWeightLight      ? @"Inter-Light"
                     : weight >= NSFontWeightSemibold ? @"Inter-SemiBold"
                     : weight >= NSFontWeightMedium   ? @"Inter-Medium"
                                                      : @"Inter-Regular";
    return [NSFont fontWithName:name size:size] ?: [NSFont systemFontOfSize:size weight:weight];
}

+ (void)observeSystemAppearance
{
    static VLCRedesignSystemAppearanceObserver *observer;
    if (@available(macOS 10.14, *)) {
        if (observer)
            return;
        observer = [[VLCRedesignSystemAppearanceObserver alloc] init];
        [NSApp addObserver:observer forKeyPath:@"effectiveAppearance" options:0 context:nil];
    }
}

+ (void)redisplay:(NSView *)view
{
    view.needsDisplay = YES;
    for (NSView *subview in view.subviews)
        [self redisplay:subview];
}

+ (void)apply
{
    [self registerFonts];
    [self observeSystemAppearance];
    if (@available(macOS 10.14, *)) {
        NSApp.appearance =
            [self.theme isEqualToString:@"system"]
                ? nil
                : [NSAppearance appearanceNamed:self.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:VLCRedesignAppearanceChanged object:nil];
}

@end
