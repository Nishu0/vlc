/*****************************************************************************
 * Native typography and color controls for subtitle appearance
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VLCRedesignColorRow : NSView <NSTextFieldDelegate>
- (instancetype)initWithTitle:(NSString *)title;
@property (nonatomic) uint32_t RGB;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, nullable) void (^changed)(uint32_t RGB);
@end

@interface VLCRedesignSizeModeRow : NSView
@property (nonatomic) BOOL pixelMode;
@property (nonatomic, copy, nullable) void (^changed)(BOOL pixelMode);
@end

NS_ASSUME_NONNULL_END
