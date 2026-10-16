/*****************************************************************************
 * VLCRedesignTrackPanel.h: In-player track and audio device selection
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import <Cocoa/Cocoa.h>

@interface VLCRedesignTrackPanel : NSView
@property (nonatomic) NSInteger selectedTab; /* video, audio, subtitles */
@property (nonatomic, copy) void (^showPreferences)(void);
@property (nonatomic, copy) void (^selectionChanged)(NSInteger tab);
- (void)refresh;
@end
