/*****************************************************************************
 * VLCRedesignAppearance.h: Appearance roles for the desktop redesign
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VLCRedesignAppearanceChanged;

@interface VLCRedesignAppearance : NSObject

@property (class, nonatomic, copy) NSString *theme;
@property (class, nonatomic) NSInteger accentIndex;
@property (class, readonly) BOOL dark;
@property (class, readonly) NSColor *backgroundColor;
@property (class, readonly) NSColor *recessedColor;
@property (class, readonly) NSColor *panelColor;
@property (class, readonly) NSColor *foregroundColor;
@property (class, readonly) NSColor *secondaryColor;
@property (class, readonly) NSColor *subduedColor;
@property (class, readonly) NSColor *borderColor;
@property (class, readonly) NSColor *accentColor;

+ (void)apply;
+ (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSColor *)colorWithRGB:(NSUInteger)rgb;

@end

NS_ASSUME_NONNULL_END
