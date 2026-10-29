/*****************************************************************************
 * VLCRedesignMusicView.h: Artwork presentation for audio playback
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Blurred artwork backdrop, large rounded artwork and "title - artist" (Figma 4767:23726)
@interface VLCRedesignMusicView : NSView

- (void)updateMedia;

@end

NS_ASSUME_NONNULL_END
