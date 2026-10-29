/*****************************************************************************
 * VLCRedesignLibraryView.h: Full-window redesigned media library
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

#import "VLCRedesignCompactBrowser.h"

NS_ASSUME_NONNULL_BEGIN

@interface VLCRedesignLibraryView : NSView

@property (readonly) VLCRedesignCompactBrowser *browser;

- (void)showSection:(VLCRedesignBrowserSection)section folder:(nullable NSURL *)folder grid:(BOOL)grid;

@end

NS_ASSUME_NONNULL_END
