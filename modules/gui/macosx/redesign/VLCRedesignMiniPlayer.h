/*****************************************************************************
 * VLCRedesignMiniPlayer.h: Floating player shown while browsing the library
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Card size from Figma 970:2703, including its 8 pt padding
extern const NSSize VLCRedesignMiniPlayerSize;

@interface VLCRedesignMiniPlayer : NSView

@property (nonatomic, copy, nullable) void (^openPlayer)(void);
@property (nonatomic, copy, nullable) void (^openQueue)(void);
// Called after a drag settles the card into the other lower corner
@property (nonatomic, copy, nullable) void (^cornerChanged)(void);
@property (nonatomic, readonly) BOOL leftCorner;

// Live video borrowed from the player; nil shows the media artwork
- (void)setVideoView:(nullable NSView *)videoView;

@end

NS_ASSUME_NONNULL_END
