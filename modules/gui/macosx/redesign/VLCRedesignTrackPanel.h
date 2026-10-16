/*****************************************************************************
 * VLCRedesignTrackPanel.h: In-player track and audio device selection
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VLCRedesignTrackPanel : NSView
@property (nonatomic) NSInteger selectedTab; /* video, audio, subtitles */
@property (nonatomic, copy, nullable) void (^showPreferences)(void);
@property (nonatomic, copy, nullable) void (^selectionChanged)(NSInteger tab);
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
