/*****************************************************************************
 * VLCRedesignAppearance.h: Appearance roles for the desktop redesign
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VLCRedesignAppearanceChanged;
// Corner radius of the content area between the player bars, measured from the video
extern const CGFloat VLCRedesignPlayerContentRadius;

@interface VLCRedesignAppearance : NSObject

@property (class, nonatomic, copy) NSString *theme;
@property (class, nonatomic) NSInteger accentIndex;
@property (class, readonly) BOOL dark;
// Appearance for redesigned views hosted inside always-dark VLC containers
@property (class, readonly) NSAppearance *themeAppearance;
@property (class, readonly) NSColor *backgroundColor;
@property (class, readonly) NSColor *recessedColor;
@property (class, readonly) NSColor *panelColor;
@property (class, readonly) NSColor *foregroundColor;
@property (class, readonly) NSColor *secondaryColor;
@property (class, readonly) NSColor *subduedColor;
@property (class, readonly) NSColor *borderColor;
@property (class, readonly) NSColor *accentColor;
// Translucent surface behind floating panels and popovers
@property (class, readonly) NSColor *overlayColor;
// Raised surface for rails, menus and previews
@property (class, readonly) NSColor *raisedColor;
@property (class, readonly) NSColor *mutedColor;
@property (class, readonly) NSColor *dividerColor;
@property (class, readonly) NSColor *hoverColor;
@property (class, readonly) NSColor *accentBackingColor;

+ (void)apply;
// Marks a view tree for redrawing after the theme or accent changes
+ (void)redisplay:(NSView *)view;
+ (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSColor *)colorWithRGB:(NSUInteger)rgb;
// Resolves against the drawing appearance on macOS 10.15 and later
+ (NSColor *)colorWithDark:(NSUInteger)dark light:(NSUInteger)light;

@end

NS_ASSUME_NONNULL_END
