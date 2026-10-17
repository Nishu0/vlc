/*****************************************************************************
 * VLCRedesignInspector.h: In-player playback, video, audio and subtitle tools
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VLCRedesignInspector : NSView
@property (nonatomic) NSInteger selectedTab;
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
