/*****************************************************************************
 * VLCRedesignSeekPreview.h: Independent seek thumbnails for the native player
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <vlc_tick.h>

NS_ASSUME_NONNULL_BEGIN
@class VLCInputItem;

@interface VLCRedesignSeekPreview : NSView
- (void)showInputItem:(VLCInputItem *)item atTime:(vlc_tick_t)time;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
