/*****************************************************************************
 * VLCRedesignIconButton.h: Icon buttons shared by the redesigned player and library
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Player artwork for the current theme, e.g. "logo" or "close"
NSImage *_Nullable VLCPlayerAsset(NSString *role);

@interface VLCPlayerIconButton : NSButton
@property (copy) NSString *assetRole;
@property BOOL transport;
@property BOOL playing;
@property BOOL selected;
@end

NS_ASSUME_NONNULL_END
