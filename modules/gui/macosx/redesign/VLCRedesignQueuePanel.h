/*****************************************************************************
 * VLCRedesignQueuePanel.h: In-player queue, bookmarks and chapters
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface VLCRedesignQueuePanel : NSView
@property (nonatomic) NSInteger selectedTab;
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
